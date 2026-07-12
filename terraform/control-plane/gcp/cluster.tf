data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.control_plane.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.control_plane.master_auth[0].cluster_ca_certificate)
}

# Unlike kubernetes_manifest, kubectl_manifest does not discover the CR schema
# during planning. It lets the first apply create GKE before applying the
# SecretProviderClass custom resources.
provider "kubectl" {
  host                   = "https://${google_container_cluster.control_plane.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.control_plane.master_auth[0].cluster_ca_certificate)
  load_config_file       = false

  # GKE registers the Secret Manager CSI CRD shortly after its API becomes
  # available. Retry the custom-resource apply while that registration settles.
  apply_retry_count = 10
}

resource "google_container_cluster" "control_plane" {
  name     = "${local.name_prefix}-cluster"
  location = var.gcp_region

  enable_autopilot = true

  network    = google_compute_network.control_plane.id
  subnetwork = google_compute_subnetwork.control_plane.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "192.168.0.16/28"
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project}.svc.id.goog"
  }

  # Enables the Secrets Store CSI driver for mounting Secret Manager secrets as files.
  secret_manager_config {
    enabled = true
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false

  depends_on = [google_project_service.required]
}
