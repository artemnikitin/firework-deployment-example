output "config_bucket_name" {
  value = google_storage_bucket.state.name
}

output "config_prefix" {
  value = local.state_prefix_with_slash
}

output "controlplane_service_mode" {
  value       = var.controlplane_service_mode
  description = "GKE control-plane layout mode: all or split."
}

output "controlplane_service_names" {
  value = var.controlplane_service_mode == "all" ? [
    "firework-controlplane",
    ] : [
    "firework-events",
    "firework-registry",
    "firework-controller",
    "firework-api",
  ]
  description = "GKE control-plane workload names used by this stack."
}

output "controlplane_network_self_link" {
  value       = google_compute_network.control_plane.self_link
  description = "Self-link of the VPC used by the GKE control plane, for data-plane VPC peering."
}

output "events_webhook_url" {
  value = "https://${trimsuffix(var.events_domain, ".")}/v1/events/github"
}

output "api_url" {
  value       = "https://${local.effective_status_domain}"
  description = "Authenticated read-only API and same-origin web UI URL"
}

output "status_domain" {
  value       = local.effective_status_domain
  description = "Public hostname for the authenticated status UI and API"
}

output "registry_url" {
  value = var.base_domain != "" ? "https://registry.${trimsuffix(var.base_domain, ".")}:${var.registry_port}" : "https://${google_compute_address.registry.address}:${var.registry_port}"
}

output "registry_server_name" {
  value = var.base_domain != "" ? "registry.${trimsuffix(var.base_domain, ".")}" : google_compute_address.registry.address
}

output "registry_internal_ip" {
  value       = google_compute_address.registry.address
  description = "Internal address assigned to the registry load balancer."
}

output "registry_allowed_cidrs" {
  value       = var.registry_allowed_cidrs
  description = "CIDRs permitted to reach the internal registry load balancer; the data-plane network CIDR must be included."
}

output "registry_ca_secret_id" {
  value = local.effective_enrollment_ca_cert_secret_id
}

output "registry_bootstrap_token_secret_id" {
  value = local.effective_bootstrap_token_secret_id
}

output "webhook_secret_id" {
  value       = local.effective_webhook_secret_id
  description = "Secret Manager secret ID holding the GitHub webhook secret. Retrieve the value with: gcloud secrets versions access latest --secret=$WEBHOOK_SECRET_ID"
}

output "operator_token_secret_id" {
  value       = local.effective_operator_token_secret_id
  description = "Secret Manager secret ID containing the operator token; retrieve its value explicitly for fireworkctl"
}
