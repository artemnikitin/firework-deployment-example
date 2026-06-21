resource "google_storage_bucket" "state" {
  name                        = var.state_bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.state_bucket_force_destroy

  versioning {
    enabled = true
  }

  labels = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_object" "controlplane_binary" {
  name         = "artifacts/firework-controlplane-${filesha256(var.firework_controlplane_path)}"
  bucket       = google_storage_bucket.state.name
  source       = var.firework_controlplane_path
  content_type = "application/octet-stream"
}
