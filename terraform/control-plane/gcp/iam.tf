resource "google_service_account" "role" {
  for_each     = toset(["events", "registry", "controller"])
  account_id   = "firework-${each.key}"
  display_name = "Firework ${each.key}"

  # Service accounts and the downstream project IAM members that reference them
  # require the IAM and Cloud Resource Manager APIs to be enabled first.
  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "state_object_admin" {
  for_each = google_service_account.role
  bucket   = google_storage_bucket.state.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_project_iam_member" "logging_writer" {
  for_each = google_service_account.role
  project  = var.gcp_project
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  for_each = google_service_account.role
  project  = var.gcp_project
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${each.value.email}"
}

locals {
  secret_readers = {
    events-tls-cert       = "events"
    events-tls-key        = "events"
    github-webhook-secret = "events"
    registry-tls-cert     = "registry"
    registry-tls-key      = "registry"
    enrollment-ca-cert    = "registry"
    enrollment-ca-key     = "registry"
    registry-bootstrap    = "registry"
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = local.secret_readers
  project   = var.gcp_project
  secret_id = google_secret_manager_secret.control_plane[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.role[each.value].email}"
}
