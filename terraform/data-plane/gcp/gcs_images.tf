resource "google_storage_bucket" "images" {
  name                        = var.images_bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = false
  }

  labels = local.common_labels
}
