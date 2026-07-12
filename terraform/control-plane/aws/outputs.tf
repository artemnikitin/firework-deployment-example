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

output "registry_url" {
  description = "Registry endpoint URL for firework-agent"
  value       = local.registry_url
}

output "registry_nlb_dns_name" {
  description = "DNS name of the registry NLB"
  value       = aws_lb.registry.dns_name
}

output "step_ca_url" {
  description = "step-ca endpoint URL for node bootstrap (empty when step-ca is disabled)"
  value       = local.step_ca_url
}

output "step_ca_nlb_dns_name" {
  description = "DNS name of the step-ca NLB (empty when step-ca is disabled)"
  value       = var.enable_step_ca ? aws_lb.step_ca[0].dns_name : ""
}

output "step_ca_service_name" {
  description = "ECS service name for step-ca (empty when step-ca is disabled)"
  value       = var.enable_step_ca ? aws_ecs_service.step_ca[0].name : ""
}

output "step_ca_provisioner_name" {
  description = "step-ca AWS IID provisioner name to use on nodes"
  value       = var.step_ca_aws_provisioner_name
}

output "step_ca_root_ca_secret_arn" {
  description = "Secrets Manager ARN containing the step-ca root CA certificate PEM for node bootstrap"
  value       = var.step_ca_root_ca_secret_arn
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster hosting control-plane services"
  value       = aws_ecs_cluster.controlplane.name
}

output "events_service_name" {
  description = "ECS service name for events role"
  value       = aws_ecs_service.events.name
}

output "registry_service_name" {
  description = "ECS service name for registry role"
  value       = aws_ecs_service.registry.name
}

output "controller_service_name" {
  description = "ECS service name for controller role"
  value       = aws_ecs_service.controller.name
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
  description = "Optional Secrets Manager ARN containing registry bootstrap token (empty when legacy token enrollment is disabled)"
  value       = local.effective_registry_bootstrap_token_secret_arn
  sensitive   = true
}

output "github_webhook_secret_secret_arn" {
  description = "Secrets Manager ARN containing the GitHub webhook secret value"
  value       = local.effective_github_webhook_secret_arn
  sensitive   = true
}

output "generated_github_webhook_secret" {
  description = "Auto-generated GitHub webhook secret value (empty when an external secret ARN was provided)"
  value       = local.auto_generated_github_webhook_secret
  sensitive   = true
}

output "generated_registry_bootstrap_token" {
  description = "Auto-generated registry bootstrap token value (empty when an external secret ARN was provided or legacy enrollment is disabled)"
  value       = local.auto_generated_registry_bootstrap_token
  sensitive   = true
}

output "generated_step_ca_password" {
  description = "Auto-generated step-ca password value (empty when an external secret ARN was provided or step-ca is disabled)"
  value       = local.auto_generated_step_ca_password
  sensitive   = true
}
