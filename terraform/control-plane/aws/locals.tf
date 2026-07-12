locals {
  state_prefix_clean = trim(var.state_prefix, "/")
  state_prefix_full  = "${local.state_prefix_clean}/"

  events_container_name     = "${var.project_name}-events"
  registry_container_name   = "${var.project_name}-registry"
  controller_container_name = "${var.project_name}-controller"

  effective_github_webhook_secret_arn             = var.github_webhook_secret_secret_arn != "" ? var.github_webhook_secret_secret_arn : try(aws_secretsmanager_secret.auto_github_webhook[0].arn, "")
  effective_events_tls_cert_secret_arn            = var.events_tls_cert_secret_arn != "" ? var.events_tls_cert_secret_arn : try(aws_secretsmanager_secret.auto_events_tls_cert[0].arn, "")
  effective_events_tls_key_secret_arn             = var.events_tls_key_secret_arn != "" ? var.events_tls_key_secret_arn : try(aws_secretsmanager_secret.auto_events_tls_key[0].arn, "")
  effective_registry_tls_cert_secret_arn          = var.registry_tls_cert_secret_arn != "" ? var.registry_tls_cert_secret_arn : try(aws_secretsmanager_secret.auto_registry_tls_cert[0].arn, "")
  effective_registry_tls_key_secret_arn           = var.registry_tls_key_secret_arn != "" ? var.registry_tls_key_secret_arn : try(aws_secretsmanager_secret.auto_registry_tls_key[0].arn, "")
  effective_registry_client_ca_secret_arn         = var.registry_client_ca_secret_arn != "" ? var.registry_client_ca_secret_arn : (var.enable_step_ca && var.step_ca_root_ca_secret_arn != "" ? var.step_ca_root_ca_secret_arn : try(aws_secretsmanager_secret.auto_registry_client_ca[0].arn, ""))
  effective_registry_enrollment_ca_secret_arn     = var.registry_enrollment_ca_secret_arn != "" ? var.registry_enrollment_ca_secret_arn : try(aws_secretsmanager_secret.auto_registry_enrollment_ca[0].arn, "")
  effective_registry_enrollment_ca_key_secret_arn = var.registry_enrollment_ca_key_secret_arn != "" ? var.registry_enrollment_ca_key_secret_arn : try(aws_secretsmanager_secret.auto_registry_enrollment_ca_key[0].arn, "")
  effective_registry_bootstrap_token_secret_arn   = var.registry_bootstrap_token_secret_arn != "" ? var.registry_bootstrap_token_secret_arn : try(aws_secretsmanager_secret.auto_registry_bootstrap_token[0].arn, "")
  effective_step_ca_password_secret_arn           = var.step_ca_password_secret_arn != "" ? var.step_ca_password_secret_arn : try(aws_secretsmanager_secret.auto_step_ca_password[0].arn, "")

  auto_generated_github_webhook_secret    = try(random_password.auto_github_webhook[0].result, "")
  auto_generated_registry_bootstrap_token = try(random_password.auto_registry_bootstrap_token[0].result, "")
  auto_generated_step_ca_password         = try(random_password.auto_step_ca_password[0].result, "")

  effective_events_acm_certificate_arn = var.events_acm_certificate_arn != "" ? var.events_acm_certificate_arn : try(aws_acm_certificate_validation.events[0].certificate_arn, "")
  events_webhook_host                  = var.events_domain_name != "" ? var.events_domain_name : aws_lb.events.dns_name

  registry_enrollment_enabled      = local.effective_registry_enrollment_ca_secret_arn != "" && local.effective_registry_enrollment_ca_key_secret_arn != ""
  registry_bootstrap_token_enabled = local.effective_registry_bootstrap_token_secret_arn != ""

  events_webhook_url = format(
    "https://%s%s/v1/events/github",
    local.events_webhook_host,
    var.events_listener_port == 443 ? "" : format(":%d", var.events_listener_port),
  )
  registry_url = format("https://%s:%d", aws_lb.registry.dns_name, var.registry_listener_port)
  step_ca_url  = var.enable_step_ca ? format("https://%s:%d", aws_lb.step_ca[0].dns_name, var.step_ca_listener_port) : ""

  step_ca_aws_accounts             = length(var.step_ca_aws_account_ids) > 0 ? var.step_ca_aws_account_ids : [data.aws_caller_identity.current.account_id]
  step_ca_aws_account_flags        = join(" ", [for account_id in local.step_ca_aws_accounts : "--aws-account ${account_id}"])
  step_ca_dns_names                = distinct(compact(concat(var.step_ca_additional_dns_names, var.enable_step_ca ? [aws_lb.step_ca[0].dns_name] : [])))
  step_ca_dns_flags                = join(" ", [for dns_name in local.step_ca_dns_names : "--dns ${dns_name}"])
  step_ca_disable_custom_sans_flag = var.step_ca_provisioner_disable_custom_sans ? "--disable-custom-sans" : ""
  step_ca_disable_tofu_flag        = var.step_ca_provisioner_disable_trust_on_first_use ? "--disable-trust-on-first-use" : ""

  secret_arns = concat(
    var.controlplane_image_pull_secret_arn != "" ? [var.controlplane_image_pull_secret_arn] : [],
    var.step_ca_image_pull_secret_arn != "" ? [var.step_ca_image_pull_secret_arn] : [],
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
      var.enable_step_ca && var.step_ca_root_ca_secret_arn != "" ? [var.step_ca_root_ca_secret_arn] : (
        local.auto_generate_registry_client_ca ? [aws_secretsmanager_secret.auto_registry_client_ca[0].arn] : []
      )
    ),
    var.registry_enrollment_ca_secret_arn != "" ? [var.registry_enrollment_ca_secret_arn] : (
      local.auto_generate_legacy_enrollment ? [aws_secretsmanager_secret.auto_registry_enrollment_ca[0].arn] : []
    ),
    var.registry_enrollment_ca_key_secret_arn != "" ? [var.registry_enrollment_ca_key_secret_arn] : (
      local.auto_generate_legacy_enrollment ? [aws_secretsmanager_secret.auto_registry_enrollment_ca_key[0].arn] : []
    ),
    var.registry_bootstrap_token_secret_arn != "" ? [var.registry_bootstrap_token_secret_arn] : (
      local.auto_generate_legacy_enrollment ? [aws_secretsmanager_secret.auto_registry_bootstrap_token[0].arn] : []
    ),
    var.step_ca_password_secret_arn != "" ? [var.step_ca_password_secret_arn] : (
      var.auto_create_demo_secrets && var.enable_step_ca ? [aws_secretsmanager_secret.auto_step_ca_password[0].arn] : []
    ),
  )
}
