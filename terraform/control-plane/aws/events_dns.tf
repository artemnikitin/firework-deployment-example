# -----------------------------------------------------------------------------
# Optional events endpoint DNS + ACM certificate automation
# -----------------------------------------------------------------------------

locals {
  events_auto_create_acm = var.events_acm_certificate_arn == "" && var.events_domain_name != ""
  events_zone_name = var.events_hosted_zone_name != "" ? trimsuffix(var.events_hosted_zone_name, ".") : (
    var.events_domain_name != "" ? replace(var.events_domain_name, "/^[^.]+\\./", "") : ""
  )
}

resource "terraform_data" "validate_events_tls" {
  lifecycle {
    precondition {
      condition     = var.events_acm_certificate_arn != "" || var.events_domain_name != ""
      error_message = "Set events_acm_certificate_arn, or set events_domain_name to auto-create an ACM certificate."
    }

    precondition {
      condition = (
        !local.events_auto_create_acm ||
        var.events_hosted_zone_name != "" ||
        length(regexall("\\.", var.events_domain_name)) >= 2
      )
      error_message = "When auto-creating events ACM cert without events_hosted_zone_name, events_domain_name must include a host label (for example events.example.com)."
    }
  }
}

data "aws_route53_zone" "events" {
  count = var.events_domain_name != "" ? 1 : 0

  name         = local.events_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "events" {
  count = local.events_auto_create_acm ? 1 : 0

  domain_name       = var.events_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-events-cert" }
}

resource "aws_route53_record" "events_cert_validation" {
  for_each = local.events_auto_create_acm ? {
    for dvo in aws_acm_certificate.events[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = data.aws_route53_zone.events[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "events" {
  count = local.events_auto_create_acm ? 1 : 0

  certificate_arn         = aws_acm_certificate.events[0].arn
  validation_record_fqdns = [for record in aws_route53_record.events_cert_validation : record.fqdn]
}

resource "aws_route53_record" "events_alias" {
  count = var.events_domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.events[0].zone_id
  name    = var.events_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.events.dns_name
    zone_id                = aws_lb.events.zone_id
    evaluate_target_health = true
  }
}
