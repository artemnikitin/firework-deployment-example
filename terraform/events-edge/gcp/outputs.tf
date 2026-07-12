output "events_domain" {
  value = trimsuffix(var.events_domain, ".")
}

output "events_address" {
  value = google_compute_global_address.events.address
}

output "events_gateway_address_name" {
  value = google_compute_global_address.events.name
}

output "events_certificate_map_name" {
  value = google_certificate_manager_certificate_map.events.name
}

output "events_certificate_name" {
  value = google_certificate_manager_certificate.events.name
}
