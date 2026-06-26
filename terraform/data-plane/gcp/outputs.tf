output "gcs_images_bucket_name" {
  value = var.images_bucket_name
}

output "tenant_load_balancer_ip" {
  value = google_compute_global_address.tenant.address
}

output "tenant_wildcard_domain" {
  value = "*.${trimsuffix(var.base_domain, ".")}"
}

output "node_service_account" {
  value = google_service_account.node.email
}
