data "google_secret_manager_secret" "registry_ca" {
  project   = var.gcp_project
  secret_id = var.registry_ca_secret_id
}

data "google_secret_manager_secret" "bootstrap_token" {
  project   = var.gcp_project
  secret_id = var.registry_bootstrap_token_secret_id
}
