resource "google_storage_bucket" "state" {
  name                        = var.state_bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  labels = local.common_labels
}
