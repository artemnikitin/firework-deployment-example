resource "google_storage_bucket" "images" {
  name                        = var.images_bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = false
  }

  labels = {
    application = "firework"
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "packer_writer" {
  count  = var.packer_service_account != "" ? 1 : 0
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.packer_service_account}"
}
