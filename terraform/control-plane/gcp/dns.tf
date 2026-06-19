data "google_dns_managed_zone" "firework" {
  name    = var.dns_zone_name
  project = var.gcp_project
}

resource "google_dns_record_set" "events" {
  name         = "${trimsuffix(var.events_domain, ".")}."
  type         = "A"
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.firework.name
  rrdatas      = [google_compute_address.events.address]
}
