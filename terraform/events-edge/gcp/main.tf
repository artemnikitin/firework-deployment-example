resource "google_project_service" "required" {
  for_each = toset([
    "certificatemanager.googleapis.com",
    "compute.googleapis.com",
  ])

  project            = var.gcp_project
  service            = each.value
  disable_on_destroy = false
}

data "google_dns_managed_zone" "events" {
  name    = var.dns_zone_name
  project = var.gcp_project
}

# This global address is intentionally owned outside the disposable control
# plane. A recreated Gateway can bind to it without changing public DNS.
resource "google_compute_global_address" "events" {
  name = "${var.edge_name}-ip"

  depends_on = [google_project_service.required]
}

resource "google_dns_record_set" "events" {
  name         = "${trimsuffix(var.events_domain, ".")}."
  type         = "A"
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.events.name
  rrdatas      = [google_compute_global_address.events.address]
}

resource "google_dns_record_set" "status" {
  name         = "${trimsuffix(var.status_domain, ".")}."
  type         = "A"
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.events.name
  rrdatas      = [google_compute_global_address.events.address]
}

# DNS authorization proves ownership independently of a live GKE Gateway, so
# Google can issue and renew this certificate before a control plane exists.
resource "google_certificate_manager_dns_authorization" "events" {
  name   = "${var.edge_name}-dns-auth"
  domain = trimsuffix(var.events_domain, ".")

  depends_on = [google_project_service.required]
}

resource "google_dns_record_set" "events_certificate_authorization" {
  name         = google_certificate_manager_dns_authorization.events.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.events.dns_resource_record[0].type
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.events.name
  rrdatas      = [google_certificate_manager_dns_authorization.events.dns_resource_record[0].data]
}

resource "google_certificate_manager_dns_authorization" "status" {
  name   = "${var.edge_name}-status-dns-auth"
  domain = trimsuffix(var.status_domain, ".")

  depends_on = [google_project_service.required]
}

resource "google_dns_record_set" "status_certificate_authorization" {
  name         = google_certificate_manager_dns_authorization.status.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.status.dns_resource_record[0].type
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.events.name
  rrdatas      = [google_certificate_manager_dns_authorization.status.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "events" {
  name = "${var.edge_name}-cert"

  managed {
    domains            = [trimsuffix(var.events_domain, ".")]
    dns_authorizations = [google_certificate_manager_dns_authorization.events.id]
  }

  depends_on = [google_dns_record_set.events_certificate_authorization]
}

resource "google_certificate_manager_certificate" "status" {
  name = "${var.edge_name}-status-cert"

  managed {
    domains            = [trimsuffix(var.status_domain, ".")]
    dns_authorizations = [google_certificate_manager_dns_authorization.status.id]
  }

  depends_on = [google_dns_record_set.status_certificate_authorization]
}

resource "google_certificate_manager_certificate_map" "events" {
  name = "${var.edge_name}-map"

  depends_on = [google_project_service.required]
}

resource "google_certificate_manager_certificate_map_entry" "events" {
  name         = "${var.edge_name}-entry"
  map          = google_certificate_manager_certificate_map.events.name
  certificates = [google_certificate_manager_certificate.events.id]
  hostname     = trimsuffix(var.events_domain, ".")
}

resource "google_certificate_manager_certificate_map_entry" "status" {
  name         = "${var.edge_name}-status-entry"
  map          = google_certificate_manager_certificate_map.events.name
  certificates = [google_certificate_manager_certificate.status.id]
  hostname     = trimsuffix(var.status_domain, ".")
}
