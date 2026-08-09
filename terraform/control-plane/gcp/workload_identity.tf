locals {
  split_controlplane_roles = {
    events = {
      ksa_name   = "firework-events"
      account_id = "${local.name_prefix}-events-sa"
      secret_ids = toset(compact([
        local.effective_webhook_secret_id,
        local.effective_events_tls_cert_secret_id,
        local.effective_events_tls_key_secret_id,
        var.github_token_secret_id,
      ]))
    }
    registry = {
      ksa_name   = "firework-registry"
      account_id = "${local.name_prefix}-registry-sa"
      secret_ids = toset([
        local.effective_bootstrap_token_secret_id,
        local.effective_registry_tls_cert_secret_id,
        local.effective_registry_tls_key_secret_id,
        local.effective_enrollment_ca_cert_secret_id,
        local.effective_enrollment_ca_key_secret_id,
      ])
    }
    controller = {
      ksa_name   = "firework-controller"
      account_id = "${local.name_prefix}-controller-sa"
      secret_ids = toset([])
    }
    api = {
      ksa_name   = "firework-api"
      account_id = "${local.name_prefix}-api-sa"
      secret_ids = toset([
        local.effective_events_tls_cert_secret_id,
        local.effective_events_tls_key_secret_id,
        local.effective_operator_token_secret_id,
      ])
    }
  }

  controlplane_roles = var.controlplane_service_mode == "split" ? local.split_controlplane_roles : {}

  all_controlplane_secret_ids = toset(compact([
    local.effective_webhook_secret_id,
    local.effective_events_tls_cert_secret_id,
    local.effective_events_tls_key_secret_id,
    var.github_token_secret_id,
    local.effective_bootstrap_token_secret_id,
    local.effective_enrollment_ca_cert_secret_id,
    local.effective_enrollment_ca_key_secret_id,
    local.effective_operator_token_secret_id,
  ]))

  controlplane_secret_accessors = merge([
    for role, cfg in local.controlplane_roles : {
      for secret_id in cfg.secret_ids : "${role}-${secret_id}" => {
        role      = role
        secret_id = secret_id
      }
    }
  ]...)
}

resource "google_service_account" "controlplane" {
  for_each     = local.controlplane_roles
  account_id   = each.value.account_id
  display_name = "Firework control-plane ${each.key} (GKE Workload Identity)"

  depends_on = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = local.controlplane_roles
  service_account_id = google_service_account.controlplane[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project}.svc.id.goog[${local.k8s_namespace}/${each.value.ksa_name}]"
}

resource "google_storage_bucket_iam_member" "state_object_admin" {
  for_each = { for role, account in google_service_account.controlplane : role => account if role != "api" }
  bucket   = google_storage_bucket.state.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_storage_bucket_iam_member" "state_object_viewer" {
  count  = var.controlplane_service_mode == "split" ? 1 : 0
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.controlplane["api"].email}"
}

resource "google_project_iam_member" "logging_writer" {
  for_each = google_service_account.controlplane
  project  = var.gcp_project
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  for_each = google_service_account.controlplane
  project  = var.gcp_project
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_secret_manager_secret_iam_member" "controlplane_accessor" {
  for_each  = local.controlplane_secret_accessors
  project   = var.gcp_project
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.controlplane[each.value.role].email}"
}

resource "google_service_account" "controlplane_all" {
  count        = var.controlplane_service_mode == "all" ? 1 : 0
  account_id   = "${local.name_prefix}-all-sa"
  display_name = "Firework all-role control plane (GKE Workload Identity)"

  depends_on = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity_all" {
  count              = var.controlplane_service_mode == "all" ? 1 : 0
  service_account_id = google_service_account.controlplane_all[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project}.svc.id.goog[${local.k8s_namespace}/firework-controlplane]"
}

resource "google_storage_bucket_iam_member" "state_object_admin_all" {
  count  = var.controlplane_service_mode == "all" ? 1 : 0
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.controlplane_all[0].email}"
}

resource "google_project_iam_member" "logging_writer_all" {
  count   = var.controlplane_service_mode == "all" ? 1 : 0
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.controlplane_all[0].email}"
}

resource "google_project_iam_member" "monitoring_writer_all" {
  count   = var.controlplane_service_mode == "all" ? 1 : 0
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.controlplane_all[0].email}"
}

resource "google_secret_manager_secret_iam_member" "controlplane_all_accessor" {
  for_each  = var.controlplane_service_mode == "all" ? local.all_controlplane_secret_ids : toset([])
  project   = var.gcp_project
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.controlplane_all[0].email}"
}
