output "config_bucket_name" {
  value = google_storage_bucket.state.name
}

output "config_prefix" {
  value = local.state_prefix_with_slash
}

output "events_webhook_url" {
  value = "https://${trimsuffix(var.events_domain, ".")}/"
}

output "registry_url" {
  value = "https://${google_compute_address.registry.address}:9443"
}

output "registry_server_name" {
  value = google_compute_address.registry.address
}

output "registry_ca_secret_id" {
  value = google_secret_manager_secret.control_plane["enrollment-ca-cert"].secret_id
}

output "registry_bootstrap_token_secret_id" {
  value = google_secret_manager_secret.control_plane["registry-bootstrap"].secret_id
}
