resource "google_service_account" "controlplane" {
  account_id   = "${local.name_prefix}-sa"
  display_name = "Firework control-plane (GKE Workload Identity)"

  depends_on = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.controlplane.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project}.svc.id.goog[firework/firework-controlplane]"
}

resource "google_storage_bucket_iam_member" "state_object_admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.controlplane.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.controlplane.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.controlplane.email}"
}

locals {
  secret_accessors = { for k, v in {
    webhook      = local.effective_webhook_secret_id
    bootstrap    = local.effective_bootstrap_token_secret_id
    ev-tls-cert  = local.effective_events_tls_cert_secret_id
    ev-tls-key   = local.effective_events_tls_key_secret_id
    reg-tls-cert = local.effective_registry_tls_cert_secret_id
    reg-tls-key  = local.effective_registry_tls_key_secret_id
    ca-cert      = local.effective_enrollment_ca_cert_secret_id
    ca-key       = local.effective_enrollment_ca_key_secret_id
    github-token = var.github_token_secret_id
  } : k => v if v != "" }
}

resource "google_secret_manager_secret_iam_member" "controlplane_accessor" {
  for_each  = local.secret_accessors
  project   = var.gcp_project
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.controlplane.email}"
}
