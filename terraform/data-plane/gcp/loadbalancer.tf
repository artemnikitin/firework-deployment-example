resource "google_compute_global_address" "tenant" {
  name = "firework-tenant-ip"
}

resource "google_compute_backend_service" "traefik" {
  name                  = "firework-traefik"
  protocol              = "HTTP"
  port_name             = "traefik"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.node.id]

  backend {
    group           = google_compute_instance_group_manager.nodes.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "tenant" {
  name            = "firework-tenant"
  default_service = google_compute_backend_service.traefik.id
}

resource "google_certificate_manager_dns_authorization" "firework" {
  name   = "firework-dns-auth"
  domain = trimsuffix(var.base_domain, ".")
}

resource "google_dns_record_set" "cert_authorization" {
  name         = google_certificate_manager_dns_authorization.firework.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.firework.dns_resource_record[0].type
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.firework.name
  rrdatas      = [google_certificate_manager_dns_authorization.firework.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "wildcard" {
  name = "firework-wildcard"
  managed {
    domains            = ["*.${trimsuffix(var.base_domain, ".")}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.firework.id]
  }
}

resource "google_certificate_manager_certificate_map" "firework" {
  name = "firework-tenant-map"
}

resource "google_certificate_manager_certificate_map_entry" "wildcard" {
  name         = "firework-wildcard"
  map          = google_certificate_manager_certificate_map.firework.name
  certificates = [google_certificate_manager_certificate.wildcard.id]
  hostname     = "*.${trimsuffix(var.base_domain, ".")}"
}

resource "google_compute_target_https_proxy" "tenant" {
  name            = "firework-tenant"
  url_map         = google_compute_url_map.tenant.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.firework.id}"
}

resource "google_compute_global_forwarding_rule" "tenant" {
  name                  = "firework-tenant-https"
  ip_address            = google_compute_global_address.tenant.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.tenant.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
