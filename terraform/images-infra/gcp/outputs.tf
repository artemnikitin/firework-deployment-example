output "images_bucket_name" {
  value       = google_storage_bucket.images.name
  description = "Pass this as images_bucket_name to the data-plane stack."
}

output "images_bucket_url" {
  value = "gs://${google_storage_bucket.images.name}"
}
