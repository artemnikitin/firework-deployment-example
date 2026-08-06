# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

data "aws_instances" "nodes" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.nodes.name]
  }
}

output "node_instance_ids" {
  description = "EC2 instance IDs currently in the nodes Auto Scaling Group"
  value       = data.aws_instances.nodes.ids
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "images_bucket_name" {
  description = "S3 bucket name for rootfs images (pre-existing, managed by CI)"
  value       = var.s3_images_bucket_id
}

output "images_bucket_arn" {
  description = "S3 bucket ARN for rootfs images (pre-existing, managed by CI)"
  value       = var.s3_images_bucket_arn
}

output "configs_bucket_prefix" {
  description = "Prefix inside the configs bucket where nodes read rendered configs from"
  value       = local.effective_s3_configs_prefix
}

output "configs_bucket_name" {
  description = "S3 bucket containing rendered configs and retained volume records"
  value       = local.effective_s3_configs_bucket_id
}

output "registry_url" {
  description = "Resolved control-plane registry URL used by nodes"
  value       = local.effective_registry_url
}

output "step_ca_url" {
  description = "Resolved step-ca URL used by nodes (empty when legacy mode is used)"
  value       = local.effective_step_ca_url
}

output "alb_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "wildcard_base_url" {
  description = "Base URL for tenant services (wildcard DNS, e.g. tenant-1.<domain>)"
  value       = "https://*.${var.domain_name}"
}

output "node_key_name" {
  description = "EC2 key pair name configured for Firework nodes"
  value       = var.node_key_name
}

output "node_ami_id" {
  description = "Resolved AMI ID used by Firework nodes"
  value       = local.effective_node_ami_id
}

output "node_agent_log_group_name" {
  description = "CloudWatch Logs group for firework-agent logs"
  value       = aws_cloudwatch_log_group.node_agent.name
}

output "node_firecracker_log_group_name" {
  description = "CloudWatch Logs group for Firecracker VM logs"
  value       = aws_cloudwatch_log_group.node_firecracker.name
}

output "alb_access_logs_bucket_name" {
  description = "S3 bucket receiving ALB access logs"
  value       = aws_s3_bucket.alb_access_logs.id
}

output "observability_dashboard_name" {
  description = "CloudWatch dashboard name for key service signals"
  value       = aws_cloudwatch_dashboard.observability.dashboard_name
}

output "agent_metric_namespace" {
  description = "CloudWatch metric namespace used by firework-agent nodes"
  value       = local.agent_metric_namespace
}

output "local_storage_enabled" {
  description = "Whether retained per-node gp3 storage is enabled"
  value       = var.enable_local_storage
}

output "shared_storage_efs_id" {
  description = "EFS file-system ID for the shared Firework storage backend"
  value       = var.enable_shared_storage ? aws_efs_file_system.shared[0].id : null
}

output "shared_storage_backend_id" {
  description = "Stable Firework shared backend identity"
  value       = var.enable_shared_storage ? var.shared_storage_backend_id : null
}

output "shared_storage_access_point_id" {
  description = "Optional EFS access point mounted by Firework nodes"
  value       = var.enable_shared_storage && var.shared_storage_use_access_point ? aws_efs_access_point.shared[0].id : null
}

output "node_network_placement" {
  description = "Whether Firecracker nodes run in public or private subnets"
  value       = var.node_network_placement
}

output "node_subnet_ids" {
  description = "Subnets the node Auto Scaling Group launches into"
  value       = local.node_subnet_ids
}

output "s3_vpc_endpoint_id" {
  description = "S3 gateway VPC endpoint serving node image, config, and package traffic"
  value       = aws_vpc_endpoint.s3.id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs. Empty in public node placement, where no NAT gateways are created."
  value       = aws_nat_gateway.main[*].id
}
