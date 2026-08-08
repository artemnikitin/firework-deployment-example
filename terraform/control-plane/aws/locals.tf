locals {
  state_prefix_clean = trim(var.state_prefix, "/")
  state_prefix_full  = "${local.state_prefix_clean}/"

  events_container_name       = "${var.project_name}-events"
  registry_container_name     = "${var.project_name}-registry"
  controller_container_name   = "${var.project_name}-controller"
  api_container_name          = "${var.project_name}-api"
  all_container_name          = "${var.project_name}-controlplane"
  controlplane_service_name   = var.controlplane_service_mode == "all" ? local.all_container_name : local.events_container_name
  controlplane_log_group_name = var.controlplane_service_mode == "all" ? "/ecs/${var.project_name}/controlplane" : "/ecs/${var.project_name}/controlplane-controller"
  controlplane_dashboard_services = var.controlplane_service_mode == "all" ? [
    { name = local.all_container_name, label = "all roles" },
    ] : [
    { name = local.events_container_name, label = "events" },
    { name = local.registry_container_name, label = "registry" },
    { name = local.controller_container_name, label = "controller" },
    { name = local.api_container_name, label = "api" },
  ]
  controlplane_running_metrics = [
    for service in local.controlplane_dashboard_services : [
      "AWS/ECS", "RunningTaskCount", "ClusterName", "${var.project_name}-controlplane", "ServiceName", service.name,
      { stat = "Average", label = "${service.label} running" },
    ]
  ]

  effective_github_webhook_secret_arn             = var.github_webhook_secret_secret_arn != "" ? var.github_webhook_secret_secret_arn : try(aws_secretsmanager_secret.auto_github_webhook[0].arn, "")
  effective_events_tls_cert_secret_arn            = var.events_tls_cert_secret_arn != "" ? var.events_tls_cert_secret_arn : try(aws_secretsmanager_secret.auto_events_tls_cert[0].arn, "")
  effective_events_tls_key_secret_arn             = var.events_tls_key_secret_arn != "" ? var.events_tls_key_secret_arn : try(aws_secretsmanager_secret.auto_events_tls_key[0].arn, "")
  effective_registry_tls_cert_secret_arn          = var.registry_tls_cert_secret_arn != "" ? var.registry_tls_cert_secret_arn : try(aws_secretsmanager_secret.auto_registry_tls_cert[0].arn, "")
  effective_registry_tls_key_secret_arn           = var.registry_tls_key_secret_arn != "" ? var.registry_tls_key_secret_arn : try(aws_secretsmanager_secret.auto_registry_tls_key[0].arn, "")
  effective_registry_client_ca_secret_arn         = var.registry_client_ca_secret_arn != "" ? var.registry_client_ca_secret_arn : try(aws_secretsmanager_secret.auto_registry_client_ca[0].arn, "")
  effective_registry_enrollment_ca_secret_arn     = var.registry_enrollment_ca_secret_arn != "" ? var.registry_enrollment_ca_secret_arn : try(aws_secretsmanager_secret.auto_registry_enrollment_ca[0].arn, "")
  effective_registry_enrollment_ca_key_secret_arn = var.registry_enrollment_ca_key_secret_arn != "" ? var.registry_enrollment_ca_key_secret_arn : try(aws_secretsmanager_secret.auto_registry_enrollment_ca_key[0].arn, "")
  effective_registry_bootstrap_token_secret_arn   = var.registry_bootstrap_token_secret_arn != "" ? var.registry_bootstrap_token_secret_arn : try(aws_secretsmanager_secret.auto_registry_bootstrap_token[0].arn, "")
  effective_operator_token_secret_arn             = var.operator_token_secret_arn != "" ? var.operator_token_secret_arn : try(aws_secretsmanager_secret.auto_operator_token[0].arn, "")

  auto_generated_github_webhook_secret    = try(random_password.auto_github_webhook[0].result, "")
  auto_generated_registry_bootstrap_token = try(random_password.auto_registry_bootstrap_token[0].result, "")

  effective_events_acm_certificate_arn = var.events_acm_certificate_arn != "" ? var.events_acm_certificate_arn : try(aws_acm_certificate_validation.events[0].certificate_arn, "")
  effective_status_domain_name = var.status_domain_name != "" ? trimsuffix(var.status_domain_name, ".") : (
    var.events_domain_name != "" ? replace(trimsuffix(var.events_domain_name, "."), "/^[^.]+\\./", "status.") : ""
  )
  effective_status_acm_certificate_arn = var.status_acm_certificate_arn != "" ? var.status_acm_certificate_arn : try(aws_acm_certificate_validation.status[0].certificate_arn, "")
  status_certificate_is_listener_default = (
    var.status_acm_certificate_arn != "" &&
    var.status_acm_certificate_arn == var.events_acm_certificate_arn
  )
  events_webhook_host = trimsuffix(var.events_domain_name, ".")

  registry_enrollment_enabled      = local.effective_registry_enrollment_ca_secret_arn != "" && local.effective_registry_enrollment_ca_key_secret_arn != ""
  registry_bootstrap_token_enabled = local.effective_registry_bootstrap_token_secret_arn != ""

  events_webhook_url = format(
    "https://%s%s/v1/events/github",
    local.events_webhook_host,
    var.events_listener_port == 443 ? "" : format(":%d", var.events_listener_port),
  )
  api_url = format(
    "https://%s%s",
    local.effective_status_domain_name,
    var.events_listener_port == 443 ? "" : format(":%d", var.events_listener_port),
  )
  registry_url = format("https://%s:%d", aws_lb.registry.dns_name, var.registry_listener_port)

  secret_arns = concat(
    var.controlplane_image_pull_secret_arn != "" ? [var.controlplane_image_pull_secret_arn] : [],
    var.github_webhook_secret_secret_arn != "" ? [var.github_webhook_secret_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_github_webhook[0].arn] : []
    ),
    var.github_token_secret_arn != "" ? [var.github_token_secret_arn] : [],
    var.events_tls_cert_secret_arn != "" ? [var.events_tls_cert_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_events_tls_cert[0].arn] : []
    ),
    var.events_tls_key_secret_arn != "" ? [var.events_tls_key_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_events_tls_key[0].arn] : []
    ),
    var.registry_tls_cert_secret_arn != "" ? [var.registry_tls_cert_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_registry_tls_cert[0].arn] : []
    ),
    var.registry_tls_key_secret_arn != "" ? [var.registry_tls_key_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_registry_tls_key[0].arn] : []
    ),
    var.registry_client_ca_secret_arn != "" ? [var.registry_client_ca_secret_arn] : (
      local.auto_generate_registry_client_ca ? [aws_secretsmanager_secret.auto_registry_client_ca[0].arn] : []
    ),
    var.registry_enrollment_ca_secret_arn != "" ? [var.registry_enrollment_ca_secret_arn] : (
      local.auto_generate_bootstrap_enrollment ? [aws_secretsmanager_secret.auto_registry_enrollment_ca[0].arn] : []
    ),
    var.registry_enrollment_ca_key_secret_arn != "" ? [var.registry_enrollment_ca_key_secret_arn] : (
      local.auto_generate_bootstrap_enrollment ? [aws_secretsmanager_secret.auto_registry_enrollment_ca_key[0].arn] : []
    ),
    var.registry_bootstrap_token_secret_arn != "" ? [var.registry_bootstrap_token_secret_arn] : (
      local.auto_generate_bootstrap_enrollment ? [aws_secretsmanager_secret.auto_registry_bootstrap_token[0].arn] : []
    ),
    var.operator_token_secret_arn != "" ? [var.operator_token_secret_arn] : (
      var.auto_create_demo_secrets ? [aws_secretsmanager_secret.auto_operator_token[0].arn] : []
    ),
  )
}
