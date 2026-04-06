# -----------------------------------------------------------------------------
# Optional demo secret bootstrap (auto-generated when ARNs are omitted)
# -----------------------------------------------------------------------------

locals {
  auto_generate_registry_client_ca = var.auto_create_demo_secrets && var.registry_client_ca_secret_arn == "" && !(var.enable_step_ca && var.step_ca_root_ca_secret_arn != "")
  auto_generate_legacy_enrollment  = var.auto_create_demo_secrets && !var.enable_step_ca && (var.registry_enrollment_ca_secret_arn == "" || var.registry_enrollment_ca_key_secret_arn == "" || var.registry_bootstrap_token_secret_arn == "")
  auto_generate_tls_material       = var.auto_create_demo_secrets && (var.events_tls_cert_secret_arn == "" || var.events_tls_key_secret_arn == "" || var.registry_tls_cert_secret_arn == "" || var.registry_tls_key_secret_arn == "" || local.auto_generate_registry_client_ca || local.auto_generate_legacy_enrollment)
}

resource "tls_private_key" "auto_root_ca" {
  count = local.auto_generate_tls_material ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "auto_root_ca" {
  count = local.auto_generate_tls_material ? 1 : 0

  private_key_pem       = tls_private_key.auto_root_ca[0].private_key_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  is_ca_certificate     = true

  subject {
    common_name  = "${var.project_name}-controlplane-auto-root"
    organization = "Firework Demo"
  }

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "tls_private_key" "auto_events_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "auto_events_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  private_key_pem = tls_private_key.auto_events_tls[0].private_key_pem
  dns_names       = distinct(compact([aws_lb.events.dns_name, "localhost"]))

  subject {
    common_name  = "${var.project_name}-events"
    organization = "Firework Demo"
  }
}

resource "tls_locally_signed_cert" "auto_events_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  cert_request_pem      = tls_cert_request.auto_events_tls[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.auto_root_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.auto_root_ca[0].cert_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "tls_private_key" "auto_registry_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "auto_registry_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  private_key_pem = tls_private_key.auto_registry_tls[0].private_key_pem
  dns_names       = distinct(compact([aws_lb.registry.dns_name, "localhost"]))

  subject {
    common_name  = "${var.project_name}-registry"
    organization = "Firework Demo"
  }
}

resource "tls_locally_signed_cert" "auto_registry_tls" {
  count = local.auto_generate_tls_material ? 1 : 0

  cert_request_pem      = tls_cert_request.auto_registry_tls[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.auto_root_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.auto_root_ca[0].cert_pem
  validity_period_hours = var.auto_generated_tls_validity_hours
  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "random_password" "auto_github_webhook" {
  count = var.auto_create_demo_secrets && var.github_webhook_secret_secret_arn == "" ? 1 : 0

  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "auto_github_webhook" {
  count = var.auto_create_demo_secrets && var.github_webhook_secret_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-github-webhook-"
  description = "Auto-generated GitHub webhook secret for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_github_webhook" {
  count = var.auto_create_demo_secrets && var.github_webhook_secret_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_github_webhook[0].id
  secret_string = random_password.auto_github_webhook[0].result
}

resource "aws_secretsmanager_secret" "auto_events_tls_cert" {
  count = var.auto_create_demo_secrets && var.events_tls_cert_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-events-tls-cert-"
  description = "Auto-generated events TLS certificate PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_events_tls_cert" {
  count = var.auto_create_demo_secrets && var.events_tls_cert_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_events_tls_cert[0].id
  secret_string = tls_locally_signed_cert.auto_events_tls[0].cert_pem
}

resource "aws_secretsmanager_secret" "auto_events_tls_key" {
  count = var.auto_create_demo_secrets && var.events_tls_key_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-events-tls-key-"
  description = "Auto-generated events TLS private key PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_events_tls_key" {
  count = var.auto_create_demo_secrets && var.events_tls_key_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_events_tls_key[0].id
  secret_string = tls_private_key.auto_events_tls[0].private_key_pem
}

resource "aws_secretsmanager_secret" "auto_registry_tls_cert" {
  count = var.auto_create_demo_secrets && var.registry_tls_cert_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-registry-tls-cert-"
  description = "Auto-generated registry TLS certificate PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_tls_cert" {
  count = var.auto_create_demo_secrets && var.registry_tls_cert_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_tls_cert[0].id
  secret_string = tls_locally_signed_cert.auto_registry_tls[0].cert_pem
}

resource "aws_secretsmanager_secret" "auto_registry_tls_key" {
  count = var.auto_create_demo_secrets && var.registry_tls_key_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-registry-tls-key-"
  description = "Auto-generated registry TLS private key PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_tls_key" {
  count = var.auto_create_demo_secrets && var.registry_tls_key_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_tls_key[0].id
  secret_string = tls_private_key.auto_registry_tls[0].private_key_pem
}

resource "aws_secretsmanager_secret" "auto_registry_client_ca" {
  count = local.auto_generate_registry_client_ca ? 1 : 0

  name_prefix = "${var.project_name}-registry-client-ca-"
  description = "Auto-generated registry client trust root CA PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_client_ca" {
  count = local.auto_generate_registry_client_ca ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_client_ca[0].id
  secret_string = tls_self_signed_cert.auto_root_ca[0].cert_pem
}

resource "aws_secretsmanager_secret" "auto_registry_enrollment_ca" {
  count = local.auto_generate_legacy_enrollment && var.registry_enrollment_ca_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-registry-enroll-ca-cert-"
  description = "Auto-generated legacy enrollment CA certificate PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_enrollment_ca" {
  count = local.auto_generate_legacy_enrollment && var.registry_enrollment_ca_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_enrollment_ca[0].id
  secret_string = tls_self_signed_cert.auto_root_ca[0].cert_pem
}

resource "aws_secretsmanager_secret" "auto_registry_enrollment_ca_key" {
  count = local.auto_generate_legacy_enrollment && var.registry_enrollment_ca_key_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-registry-enroll-ca-key-"
  description = "Auto-generated legacy enrollment CA private key PEM for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_enrollment_ca_key" {
  count = local.auto_generate_legacy_enrollment && var.registry_enrollment_ca_key_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_enrollment_ca_key[0].id
  secret_string = tls_private_key.auto_root_ca[0].private_key_pem
}

resource "random_password" "auto_registry_bootstrap_token" {
  count = local.auto_generate_legacy_enrollment && var.registry_bootstrap_token_secret_arn == "" ? 1 : 0

  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "auto_registry_bootstrap_token" {
  count = local.auto_generate_legacy_enrollment && var.registry_bootstrap_token_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-registry-bootstrap-token-"
  description = "Auto-generated legacy registry bootstrap token for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_registry_bootstrap_token" {
  count = local.auto_generate_legacy_enrollment && var.registry_bootstrap_token_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_registry_bootstrap_token[0].id
  secret_string = random_password.auto_registry_bootstrap_token[0].result
}

resource "random_password" "auto_step_ca_password" {
  count = var.auto_create_demo_secrets && var.enable_step_ca && var.step_ca_password_secret_arn == "" ? 1 : 0

  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "auto_step_ca_password" {
  count = var.auto_create_demo_secrets && var.enable_step_ca && var.step_ca_password_secret_arn == "" ? 1 : 0

  name_prefix = "${var.project_name}-step-ca-password-"
  description = "Auto-generated step-ca password for ${var.project_name} control-plane"
}

resource "aws_secretsmanager_secret_version" "auto_step_ca_password" {
  count = var.auto_create_demo_secrets && var.enable_step_ca && var.step_ca_password_secret_arn == "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.auto_step_ca_password[0].id
  secret_string = random_password.auto_step_ca_password[0].result
}
