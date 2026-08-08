# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "config_bucket_name" {
  description = "S3 bucket name used for control-plane state and rendered configs"
  value       = aws_s3_bucket.configs.id
}

output "config_bucket_arn" {
  description = "S3 bucket ARN used for control-plane state and rendered configs"
  value       = aws_s3_bucket.configs.arn
}

output "config_prefix" {
  description = "S3 prefix where rendered node configs are published"
  value       = local.state_prefix_full
}

output "events_webhook_url" {
  description = "GitHub webhook URL for events role"
  value       = local.events_webhook_url
}

output "api_url" {
  description = "Authenticated read-only API and same-origin web UI URL"
  value       = local.api_url
}

output "status_domain_name" {
  description = "Public hostname for the authenticated status UI and API"
  value       = local.effective_status_domain_name
}

output "events_alb_dns_name" {
  description = "DNS name of the events ALB"
  value       = aws_lb.events.dns_name
}

output "events_domain_name" {
  description = "Custom DNS name configured for events endpoint (empty when not set)"
  value       = var.events_domain_name
}

output "events_acm_certificate_arn" {
  description = "ACM certificate ARN used by the events HTTPS listener"
  value       = local.effective_events_acm_certificate_arn
}

output "status_acm_certificate_arn" {
  description = "ACM certificate ARN used for the status UI/API hostname"
  value       = local.effective_status_acm_certificate_arn
}

output "registry_url" {
  description = "Registry endpoint URL for firework-agent"
  value       = local.registry_url
}

output "registry_server_name" {
  description = "TLS server name for the registry endpoint"
  value       = aws_lb.registry.dns_name
}

output "registry_nlb_dns_name" {
  description = "DNS name of the registry NLB"
  value       = aws_lb.registry.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster hosting control-plane services"
  value       = aws_ecs_cluster.controlplane.name
}

output "events_service_name" {
  description = "ECS service name serving the events role"
  value       = var.controlplane_service_mode == "all" ? local.all_service_name : local.events_service_name
}

output "registry_service_name" {
  description = "ECS service name serving the registry role"
  value       = var.controlplane_service_mode == "all" ? local.all_service_name : local.registry_service_name
}

output "controller_service_name" {
  description = "ECS service name serving the controller role"
  value       = var.controlplane_service_mode == "all" ? local.all_service_name : local.controller_service_name
}

output "api_service_name" {
  description = "ECS service name serving the read-only API role"
  value       = var.controlplane_service_mode == "all" ? local.all_service_name : local.api_service_name
}

output "controlplane_service_name" {
  description = "ECS service name serving the control plane"
  value       = local.controlplane_service_name
}

output "controlplane_service_names" {
  description = "ECS service names serving the control plane roles"
  value = var.controlplane_service_mode == "all" ? [
    local.all_service_name,
    ] : [
    local.events_service_name,
    local.registry_service_name,
    local.controller_service_name,
    local.api_service_name,
  ]
}

output "controlplane_log_group_name" {
  description = "CloudWatch log group containing the controller or combined control-plane logs"
  value       = local.controlplane_log_group_name
}

output "events_log_group_name" {
  description = "CloudWatch log group for events service"
  value       = aws_cloudwatch_log_group.events.name
}

output "registry_log_group_name" {
  description = "CloudWatch log group for registry service"
  value       = aws_cloudwatch_log_group.registry.name
}

output "controller_log_group_name" {
  description = "CloudWatch log group for controller service"
  value       = aws_cloudwatch_log_group.controller.name
}

output "api_log_group_name" {
  description = "CloudWatch log group for read-only API service"
  value       = aws_cloudwatch_log_group.api.name
}

output "observability_dashboard_name" {
  description = "CloudWatch dashboard name for control-plane services"
  value       = aws_cloudwatch_dashboard.controlplane.dashboard_name
}

output "registry_client_ca_secret_arn" {
  description = "Secrets Manager ARN containing the registry trust root CA PEM (shared with nodes for TLS verification)"
  value       = local.effective_registry_client_ca_secret_arn
  sensitive   = true
}

output "registry_bootstrap_token_secret_arn" {
  description = "Secrets Manager ARN containing the registry bootstrap token"
  value       = local.effective_registry_bootstrap_token_secret_arn
  sensitive   = true
}

output "github_webhook_secret_secret_arn" {
  description = "Secrets Manager ARN containing the GitHub webhook secret value"
  value       = local.effective_github_webhook_secret_arn
  sensitive   = true
}

output "operator_token_secret_arn" {
  description = "Secrets Manager ARN containing the dedicated operator token; retrieve the value explicitly when configuring fireworkctl"
  value       = local.effective_operator_token_secret_arn
  sensitive   = true
}

output "generated_github_webhook_secret" {
  description = "Auto-generated GitHub webhook secret value (empty when an external secret ARN was provided)"
  value       = local.auto_generated_github_webhook_secret
  sensitive   = true
}

output "generated_registry_bootstrap_token" {
  description = "Auto-generated registry bootstrap token value (empty when an external secret ARN was provided)"
  value       = local.auto_generated_registry_bootstrap_token
  sensitive   = true
}
