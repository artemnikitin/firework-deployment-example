resource "google_service_account" "node" {
  account_id   = "${local.name_prefix}-sa"
  display_name = "Firework node"
}

resource "google_storage_bucket_iam_member" "images_reader" {
  bucket = var.images_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.node.email}"
}

resource "google_storage_bucket_iam_member" "configs_reader" {
  bucket = local.effective_config_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.node.email}"
}

resource "google_secret_manager_secret_iam_member" "registry_ca" {
  project   = var.gcp_project
  secret_id = local.effective_registry_ca_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.node.email}"
}

resource "google_secret_manager_secret_iam_member" "bootstrap_token" {
  project   = var.gcp_project
  secret_id = local.effective_registry_bootstrap_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_logging" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}
