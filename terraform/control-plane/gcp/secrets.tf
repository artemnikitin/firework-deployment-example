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

resource "random_password" "webhook_secret" {
  length  = 48
  special = false
}

resource "random_password" "bootstrap_token" {
  length  = 48
  special = false
}

resource "tls_private_key" "enrollment_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "enrollment_ca" {
  private_key_pem       = tls_private_key.enrollment_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 8760
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name  = "Firework GCP enrollment CA"
    organization = "Firework"
  }
}

resource "tls_private_key" "registry_server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "registry_server" {
  private_key_pem = tls_private_key.registry_server.private_key_pem
  ip_addresses    = [google_compute_address.registry.address]

  subject {
    common_name  = google_compute_address.registry.address
    organization = "Firework"
  }
}

resource "tls_locally_signed_cert" "registry_server" {
  cert_request_pem      = tls_cert_request.registry_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.enrollment_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.enrollment_ca.cert_pem
  validity_period_hours = 8760
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "acme_registration" "events" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email
}

resource "acme_certificate" "events" {
  account_key_pem = acme_registration.events.account_key_pem
  common_name     = var.events_domain

  dns_challenge {
    provider = "gcloud"
    config = {
      GCE_PROJECT             = var.gcp_project
      GCE_PROPAGATION_TIMEOUT = "180"
    }
  }

  # Check DNS-01 propagation against public resolvers instead of the operator's
  # local/system resolver, which may be slow or unreachable and otherwise causes
  # "propagation: time limit exceeded ... i/o timeout" failures.
  recursive_nameservers = var.acme_recursive_nameservers
}

locals {
  secret_payloads = {
    events-tls-cert       = "${acme_certificate.events.certificate_pem}${acme_certificate.events.issuer_pem}"
    events-tls-key        = acme_certificate.events.private_key_pem
    github-webhook-secret = random_password.webhook_secret.result
    registry-tls-cert     = tls_locally_signed_cert.registry_server.cert_pem
    registry-tls-key      = tls_private_key.registry_server.private_key_pem
    enrollment-ca-cert    = tls_self_signed_cert.enrollment_ca.cert_pem
    enrollment-ca-key     = tls_private_key.enrollment_ca.private_key_pem
    registry-bootstrap    = random_password.bootstrap_token.result
  }
}

resource "google_secret_manager_secret" "control_plane" {
  for_each  = local.secret_payloads
  secret_id = "firework-${each.key}"

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "control_plane" {
  for_each    = local.secret_payloads
  secret      = google_secret_manager_secret.control_plane[each.key].id
  secret_data = each.value
}
