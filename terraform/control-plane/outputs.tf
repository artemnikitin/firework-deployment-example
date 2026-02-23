# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "config_bucket_name" {
  description = "S3 bucket name for enriched node configs"
  value       = aws_s3_bucket.configs.id
}

output "config_bucket_arn" {
  description = "S3 bucket ARN for enriched node configs"
  value       = aws_s3_bucket.configs.arn
}

output "enricher_function_name" {
  description = "Enricher Lambda function name"
  value       = aws_lambda_function.enricher.function_name
}

output "webhook_url" {
  description = "GitHub webhook URL (POST to this endpoint)"
  value       = "${aws_apigatewayv2_api.webhook.api_endpoint}/webhook"
}

output "enricher_log_group_name" {
  description = "CloudWatch log group for enricher Lambda logs"
  value       = aws_cloudwatch_log_group.enricher.name
}

output "webhook_access_log_group_name" {
  description = "CloudWatch log group for API Gateway webhook access logs"
  value       = aws_cloudwatch_log_group.webhook_access.name
}

output "observability_dashboard_name" {
  description = "CloudWatch dashboard name for enricher observability"
  value       = aws_cloudwatch_dashboard.observability.dashboard_name
}

output "scheduler_function_name" {
  description = "Scheduler Lambda function name"
  value       = aws_lambda_function.scheduler.function_name
}

output "scheduler_function_arn" {
  description = "Scheduler Lambda function ARN (used by enricher to invoke it)"
  value       = aws_lambda_function.scheduler.arn
}

output "scheduler_log_group_name" {
  description = "CloudWatch log group for scheduler Lambda logs"
  value       = aws_cloudwatch_log_group.scheduler.name
}
