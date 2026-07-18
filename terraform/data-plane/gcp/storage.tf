resource "google_project_service" "filestore" {
  count = var.enable_shared_storage ? 1 : 0

  project            = var.gcp_project
  service            = "file.googleapis.com"
  disable_on_destroy = false
}

resource "google_filestore_instance" "shared" {
  count = var.enable_shared_storage ? 1 : 0

  name                        = "${local.name_prefix}-shared"
  location                    = var.gcp_region
  tier                        = var.filestore_tier
  protocol                    = "NFS_V4_1"
  description                 = "Firework shared persistent-volume image backend"
  deletion_protection_enabled = var.filestore_deletion_protection
  deletion_protection_reason  = var.filestore_deletion_protection ? "Firework volumes are retained by default" : null
  labels                      = local.common_labels

  file_shares {
    name        = "firework"
    capacity_gb = var.filestore_capacity_gib

    nfs_export_options {
      ip_ranges   = [var.network_cidr]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network      = google_compute_network.data_plane.name
    modes        = ["MODE_IPV4"]
    connect_mode = "DIRECT_PEERING"
  }

  depends_on = [google_project_service.filestore]
}

resource "google_compute_firewall" "filestore_nfs_egress" {
  count = var.enable_shared_storage ? 1 : 0

  name      = "${local.name_prefix}-filestore-egress"
  network   = google_compute_network.data_plane.name
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["2049"]
  }

  destination_ranges = ["${google_filestore_instance.shared[0].networks[0].ip_addresses[0]}/32"]
  target_tags        = [local.node_network_tag]
}
