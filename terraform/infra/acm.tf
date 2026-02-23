# -----------------------------------------------------------------------------
# ACM — TLS certificate for the ALB.
#
# Two modes controlled by var.acm_create_certificate:
#
#   true  (default) — create and DNS-validate a new wildcard certificate.
#                     Route53 CNAME records are managed automatically.
#
#   false           — use a pre-existing certificate supplied via
#                     var.acm_certificate_arn (no resources created here).
# -----------------------------------------------------------------------------

# Validate that a cert ARN is provided when not creating one.
resource "terraform_data" "validate_acm" {
  lifecycle {
    precondition {
      condition     = var.acm_create_certificate || var.acm_certificate_arn != ""
      error_message = "acm_certificate_arn must be set when acm_create_certificate is false."
    }
  }
}

resource "aws_acm_certificate" "main" {
  count = var.acm_create_certificate ? 1 : 0

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.acm_create_certificate ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count = var.acm_create_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

locals {
  # Resolves to the validated ARN regardless of which mode is active.
  certificate_arn = var.acm_create_certificate ? aws_acm_certificate_validation.main[0].certificate_arn : var.acm_certificate_arn
}
