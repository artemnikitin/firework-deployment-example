resource "google_compute_network" "control_plane" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "control_plane" {
  name                     = "${local.name_prefix}-subnet"
  region                   = var.gcp_region
  network                  = google_compute_network.control_plane.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.21.0.0/20"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.22.0.0/24"
  }
}

resource "google_compute_router" "control_plane" {
  name    = "${local.name_prefix}-router"
  region  = var.gcp_region
  network = google_compute_network.control_plane.id
}

resource "google_compute_router_nat" "control_plane" {
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.control_plane.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Static external IPs for the events and registry Kubernetes LoadBalancer Services.
# GKE manages the underlying firewall rules for LoadBalancer-type Services.
resource "google_compute_address" "events" {
  name   = "${local.name_prefix}-events-ip"
  region = var.gcp_region

  depends_on = [google_project_service.required]
}

resource "google_compute_address" "registry" {
  name   = "${local.name_prefix}-registry-ip"
  region = var.gcp_region

  depends_on = [google_project_service.required]
}
