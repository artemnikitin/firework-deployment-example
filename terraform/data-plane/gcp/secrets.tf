data "google_secret_manager_secret" "registry_ca" {
  # The control-plane state may already be empty during data-plane teardown.
  # Do not try to refresh a data source with an empty secret ID in that case.
  count     = try(local.effective_registry_ca_secret_id == null ? 0 : (local.effective_registry_ca_secret_id != "" ? 1 : 0), 0)
  project   = var.gcp_project
  secret_id = local.effective_registry_ca_secret_id
}

data "google_secret_manager_secret" "bootstrap_token" {
  # The control-plane state may already be empty during data-plane teardown.
  # Do not try to refresh a data source with an empty secret ID in that case.
  count     = try(local.effective_registry_bootstrap_token_secret_id == null ? 0 : (local.effective_registry_bootstrap_token_secret_id != "" ? 1 : 0), 0)
  project   = var.gcp_project
  secret_id = local.effective_registry_bootstrap_token_secret_id
}
