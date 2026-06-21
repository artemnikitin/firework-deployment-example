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

resource "google_compute_firewall" "public_endpoints" {
  name    = "${local.name_prefix}-public-endpoints"
  network = google_compute_network.control_plane.name

  allow {
    protocol = "tcp"
    ports    = ["443", "9443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["firework-control-plane"]
}

resource "google_compute_firewall" "health_checks" {
  name    = "${local.name_prefix}-health-checks"
  network = google_compute_network.control_plane.name

  allow {
    protocol = "tcp"
    ports    = ["443", "9443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags   = ["firework-control-plane"]
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "${local.name_prefix}-iap-ssh"
  network = google_compute_network.control_plane.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["firework-control-plane"]
}

resource "google_compute_firewall" "internal" {
  name    = "${local.name_prefix}-internal"
  network = google_compute_network.control_plane.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.network_cidr]
  target_tags   = ["firework-control-plane"]
}
