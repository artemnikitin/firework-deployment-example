# -----------------------------------------------------------------------------
# Optional demo secret bootstrap (auto-generated when secret IDs are omitted)
# -----------------------------------------------------------------------------

locals {
  # Generate all TLS/PKI material together from a single root CA when any of
  # the six PKI secret IDs is absent.
  auto_generate_tls_material = var.auto_create_demo_secrets && (
    var.events_tls_cert_secret_id == "" ||
    var.events_tls_key_secret_id == "" ||
    var.registry_tls_cert_secret_id == "" ||
    var.registry_tls_key_secret_id == "" ||
    var.enrollment_ca_cert_secret_id == "" ||
    var.enrollment_ca_key_secret_id == ""
  )
  auto_generate_bootstrap = var.auto_create_demo_secrets && var.bootstrap_token_secret_id == ""

  # Effective secret IDs — prefer explicit vars, fall back to auto-generated.
  effective_webhook_secret_id            = var.webhook_secret_id
  effective_bootstrap_token_secret_id    = var.bootstrap_token_secret_id != "" ? var.bootstrap_token_secret_id : (local.auto_generate_bootstrap ? google_secret_manager_secret.auto_bootstrap_token[0].secret_id : "")
  effective_events_tls_cert_secret_id    = var.events_tls_cert_secret_id != "" ? var.events_tls_cert_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_events_tls_cert[0].secret_id : "")
  effective_events_tls_key_secret_id     = var.events_tls_key_secret_id != "" ? var.events_tls_key_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_events_tls_key[0].secret_id : "")
  effective_registry_tls_cert_secret_id  = var.registry_tls_cert_secret_id != "" ? var.registry_tls_cert_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_registry_tls_cert[0].secret_id : "")
  effective_registry_tls_key_secret_id   = var.registry_tls_key_secret_id != "" ? var.registry_tls_key_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_registry_tls_key[0].secret_id : "")
  effective_enrollment_ca_cert_secret_id = var.enrollment_ca_cert_secret_id != "" ? var.enrollment_ca_cert_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_enrollment_ca_cert[0].secret_id : "")
  effective_enrollment_ca_key_secret_id  = var.enrollment_ca_key_secret_id != "" ? var.enrollment_ca_key_secret_id : (local.auto_generate_tls_material ? google_secret_manager_secret.auto_enrollment_ca_key[0].secret_id : "")
}

# --- Enrollment CA (root of trust for all generated certs) ---

resource "tls_private_key" "auto_root_ca" {
  count       = local.auto_generate_tls_material ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "auto_root_ca" {
  count = local.auto_generate_tls_material ? 1 : 0

  private_key_pem       = tls_private_key.auto_root_ca[0].private_key_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  is_ca_certificate     = true

  subject {
    common_name  = "${local.name_prefix}-enrollment-ca"
    organization = "Firework Demo"
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature", "key_encipherment"]
}

# --- Events TLS cert (covers events_domain) ---

resource "tls_private_key" "auto_events_tls" {
  count       = local.auto_generate_tls_material ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "auto_events_tls" {
  count           = local.auto_generate_tls_material ? 1 : 0
  private_key_pem = tls_private_key.auto_events_tls[0].private_key_pem
  dns_names       = [trimsuffix(var.events_domain, ".")]

  subject {
    common_name  = "${local.name_prefix}-events"
    organization = "Firework Demo"
  }
}

resource "tls_locally_signed_cert" "auto_events_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  cert_request_pem      = tls_cert_request.auto_events_tls[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.auto_root_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.auto_root_ca[0].cert_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

# --- Registry TLS cert (covers static IP or registry.<base_domain> DNS SAN) ---

resource "tls_private_key" "auto_registry_tls" {
  count       = local.auto_generate_tls_material ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "auto_registry_tls" {
  count           = local.auto_generate_tls_material ? 1 : 0
  private_key_pem = tls_private_key.auto_registry_tls[0].private_key_pem
  ip_addresses    = var.base_domain == "" ? [google_compute_address.registry.address] : []
  dns_names       = var.base_domain != "" ? ["registry.${trimsuffix(var.base_domain, ".")}"] : []

  subject {
    common_name  = "${local.name_prefix}-registry"
    organization = "Firework Demo"
  }
}

resource "tls_locally_signed_cert" "auto_registry_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  cert_request_pem      = tls_cert_request.auto_registry_tls[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.auto_root_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.auto_root_ca[0].cert_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

# --- Bootstrap token ---

resource "random_password" "auto_bootstrap_token" {
  count   = local.auto_generate_bootstrap ? 1 : 0
  length  = 40
  special = false
}

# --- GCP Secret Manager secrets ---

resource "google_secret_manager_secret" "auto_enrollment_ca_cert" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-enrollment-ca-cert"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_enrollment_ca_cert" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_enrollment_ca_cert[0].id
  secret_data = tls_self_signed_cert.auto_root_ca[0].cert_pem
}

resource "google_secret_manager_secret" "auto_enrollment_ca_key" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-enrollment-ca-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_enrollment_ca_key" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_enrollment_ca_key[0].id
  secret_data = tls_private_key.auto_root_ca[0].private_key_pem
}

resource "google_secret_manager_secret" "auto_events_tls_cert" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-events-tls-cert"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_events_tls_cert" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_events_tls_cert[0].id
  secret_data = tls_locally_signed_cert.auto_events_tls[0].cert_pem
}

resource "google_secret_manager_secret" "auto_events_tls_key" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-events-tls-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_events_tls_key" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_events_tls_key[0].id
  secret_data = tls_private_key.auto_events_tls[0].private_key_pem
}

resource "google_secret_manager_secret" "auto_registry_tls_cert" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-registry-tls-cert"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_registry_tls_cert" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_registry_tls_cert[0].id
  secret_data = tls_locally_signed_cert.auto_registry_tls[0].cert_pem
}

resource "google_secret_manager_secret" "auto_registry_tls_key" {
  count     = local.auto_generate_tls_material ? 1 : 0
  secret_id = "${local.name_prefix}-registry-tls-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_registry_tls_key" {
  count       = local.auto_generate_tls_material ? 1 : 0
  secret      = google_secret_manager_secret.auto_registry_tls_key[0].id
  secret_data = tls_private_key.auto_registry_tls[0].private_key_pem
}

resource "google_secret_manager_secret" "auto_bootstrap_token" {
  count     = local.auto_generate_bootstrap ? 1 : 0
  secret_id = "${local.name_prefix}-bootstrap-token"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "auto_bootstrap_token" {
  count       = local.auto_generate_bootstrap ? 1 : 0
  secret      = google_secret_manager_secret.auto_bootstrap_token[0].id
  secret_data = random_password.auto_bootstrap_token[0].result
}
