output "config_bucket_name" {
  value = google_storage_bucket.state.name
}

output "config_prefix" {
  value = local.state_prefix_with_slash
}

output "events_webhook_url" {
  value = "https://${trimsuffix(var.events_domain, ".")}/v1/events/github"
}

output "registry_url" {
  value = var.base_domain != "" ? "https://registry.${trimsuffix(var.base_domain, ".")}:9443" : "https://${google_compute_address.registry.address}:9443"
}

output "registry_server_name" {
  value = var.base_domain != "" ? "registry.${trimsuffix(var.base_domain, ".")}" : google_compute_address.registry.address
}

output "registry_ca_secret_id" {
  value = var.enrollment_ca_cert_secret_id
}

output "registry_bootstrap_token_secret_id" {
  value = var.bootstrap_token_secret_id
}

output "webhook_secret_id" {
  value       = var.webhook_secret_id
  description = "Secret Manager secret ID holding the GitHub webhook secret. Retrieve the value with: gcloud secrets versions access latest --secret=$WEBHOOK_SECRET_ID"
}
