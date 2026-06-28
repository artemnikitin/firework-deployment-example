resource "google_compute_network" "data_plane" {
  name                    = "firework-data-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "nodes" {
  name                     = "firework-node-subnet"
  region                   = var.gcp_region
  network                  = google_compute_network.data_plane.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "nodes" {
  name    = "firework-node-router"
  region  = var.gcp_region
  network = google_compute_network.data_plane.id
}

resource "google_compute_router_nat" "nodes" {
  name                               = "firework-node-nat"
  router                             = google_compute_router.nodes.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "intra_subnet" {
  name    = "firework-node-internal"
  network = google_compute_network.data_plane.name

  allow {
    protocol = "all"
  }

  source_ranges = [var.network_cidr]
  target_tags   = ["firework-node"]
}

resource "google_compute_firewall" "load_balancer" {
  name    = "firework-node-lb-health"
  network = google_compute_network.data_plane.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["firework-node"]
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "firework-node-iap-ssh"
  network = google_compute_network.data_plane.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["firework-node"]
}
