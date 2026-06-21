resource "google_compute_region_health_check" "events" {
  name   = "${local.name_prefix}-events"
  region = var.gcp_region

  tcp_health_check {
    port = 443
  }
}

resource "google_compute_region_health_check" "registry" {
  name   = "${local.name_prefix}-registry"
  region = var.gcp_region

  tcp_health_check {
    port = 9443
  }
}

resource "google_compute_region_backend_service" "events" {
  name                  = "${local.name_prefix}-events"
  region                = var.gcp_region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.events.id]

  backend {
    group          = google_compute_instance_group.events.id
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_region_backend_service" "registry" {
  name                  = "${local.name_prefix}-registry"
  region                = var.gcp_region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.registry.id]

  backend {
    group          = google_compute_instance_group.registry.id
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "events" {
  name                  = "${local.name_prefix}-events"
  region                = var.gcp_region
  ip_address            = google_compute_address.events.id
  ip_protocol           = "TCP"
  ports                 = ["443"]
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.events.id
}

resource "google_compute_forwarding_rule" "registry" {
  name                  = "${local.name_prefix}-registry"
  region                = var.gcp_region
  ip_address            = google_compute_address.registry.id
  ip_protocol           = "TCP"
  ports                 = ["9443"]
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.registry.id
}
