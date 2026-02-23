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
