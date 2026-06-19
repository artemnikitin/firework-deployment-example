data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

locals {
  role_config = {
    events = {
      service_account = google_service_account.role["events"].email
    }
    registry = {
      service_account = google_service_account.role["registry"].email
    }
    controller = {
      service_account = google_service_account.role["controller"].email
    }
  }
}

resource "google_compute_instance" "role" {
  for_each     = local.role_config
  name         = "${local.name_prefix}-${each.key}"
  zone         = var.gcp_zone
  machine_type = var.machine_type
  tags         = ["firework-control-plane"]
  labels       = merge(local.common_labels, { role = each.key })

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.control_plane.id
    access_config {}
  }

  service_account {
    email  = each.value.service_account
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/templates/controlplane-startup.sh.tpl", {
    role                          = each.key
    gcp_project                   = var.gcp_project
    state_bucket                  = google_storage_bucket.state.name
    state_prefix                  = var.state_prefix
    firework_controlplane_version = var.firework_controlplane_version
    git_repo_url                  = var.git_repo_url
    target_branch                 = var.target_branch
    config_dir                    = var.config_dir
    node_stale_ttl                = var.node_stale_ttl
    events_tls_cert_secret        = google_secret_manager_secret.control_plane["events-tls-cert"].secret_id
    events_tls_key_secret         = google_secret_manager_secret.control_plane["events-tls-key"].secret_id
    webhook_secret                = google_secret_manager_secret.control_plane["github-webhook-secret"].secret_id
    registry_tls_cert_secret      = google_secret_manager_secret.control_plane["registry-tls-cert"].secret_id
    registry_tls_key_secret       = google_secret_manager_secret.control_plane["registry-tls-key"].secret_id
    enrollment_ca_cert_secret     = google_secret_manager_secret.control_plane["enrollment-ca-cert"].secret_id
    enrollment_ca_key_secret      = google_secret_manager_secret.control_plane["enrollment-ca-key"].secret_id
    bootstrap_token_secret        = google_secret_manager_secret.control_plane["registry-bootstrap"].secret_id
  })

  depends_on = [
    google_secret_manager_secret_iam_member.accessor,
    google_storage_bucket_iam_member.state_object_admin,
  ]
}

resource "google_compute_instance_group" "events" {
  name      = "${local.name_prefix}-events-group"
  zone      = var.gcp_zone
  instances = [google_compute_instance.role["events"].id]
}

resource "google_compute_instance_group" "registry" {
  name      = "${local.name_prefix}-registry-group"
  zone      = var.gcp_zone
  instances = [google_compute_instance.role["registry"].id]
}
