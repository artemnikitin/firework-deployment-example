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

output "local_storage_enabled" {
  value       = var.enable_local_storage
  description = "Whether retained per-instance Hyperdisk storage is enabled"
}

output "filestore_ip" {
  value       = var.enable_shared_storage ? google_filestore_instance.shared[0].networks[0].ip_addresses[0] : null
  description = "Regional Filestore NFSv4.1 address"
}

output "filestore_share" {
  value       = var.enable_shared_storage ? google_filestore_instance.shared[0].file_shares[0].name : null
  description = "Filestore export name mounted by nodes"
}

output "shared_storage_backend_id" {
  value       = var.enable_shared_storage ? var.shared_storage_backend_id : null
  description = "Stable Firework shared backend identity"
}
