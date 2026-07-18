# -----------------------------------------------------------------------------
# Optional events endpoint DNS + ACM certificate automation
# -----------------------------------------------------------------------------

locals {
  events_auto_create_acm = var.events_acm_certificate_arn == "" && var.events_domain_name != ""
  events_zone_name = var.events_hosted_zone_name != "" ? trimsuffix(var.events_hosted_zone_name, ".") : (
    var.events_domain_name != "" ? replace(var.events_domain_name, "/^[^.]+\\./", "") : ""
  )
  status_auto_create_acm = var.status_acm_certificate_arn == "" && local.effective_status_domain_name != ""
  status_zone_name = var.status_hosted_zone_name != "" ? trimsuffix(var.status_hosted_zone_name, ".") : (
    local.effective_status_domain_name != "" ? replace(local.effective_status_domain_name, "/^[^.]+\\./", "") : ""
  )
}

resource "terraform_data" "validate_events_tls" {
  lifecycle {
    precondition {
      condition     = var.events_domain_name != ""
      error_message = "events_domain_name is required so webhook traffic can be isolated from the status UI/API by hostname."
    }

    precondition {
      condition     = local.effective_status_domain_name != ""
      error_message = "Set status_domain_name or events_domain_name so Terraform can derive the status UI/API hostname."
    }

    precondition {
      condition     = trimsuffix(var.events_domain_name, ".") != local.effective_status_domain_name
      error_message = "events_domain_name and status_domain_name must be different hostnames."
    }

    precondition {
      condition = (
        !local.events_auto_create_acm ||
        var.events_hosted_zone_name != "" ||
        length(regexall("\\.", var.events_domain_name)) >= 2
      )
      error_message = "When auto-creating events ACM cert without events_hosted_zone_name, events_domain_name must include a host label (for example events.example.com)."
    }

    precondition {
      condition = (
        !local.status_auto_create_acm ||
        var.status_hosted_zone_name != "" ||
        length(regexall("\\.", local.effective_status_domain_name)) >= 2
      )
      error_message = "When auto-creating the status ACM cert without status_hosted_zone_name, the effective status domain must include a host label (for example status.example.com)."
    }
  }
}

data "aws_route53_zone" "events" {
  count = var.events_domain_name != "" ? 1 : 0

  name         = local.events_zone_name
  private_zone = false
}

data "aws_route53_zone" "status" {
  count = local.effective_status_domain_name != "" ? 1 : 0

  name         = local.status_zone_name
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

resource "aws_acm_certificate" "status" {
  count = local.status_auto_create_acm ? 1 : 0

  domain_name       = local.effective_status_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-status-cert" }
}

resource "aws_route53_record" "status_cert_validation" {
  for_each = local.status_auto_create_acm ? {
    for dvo in aws_acm_certificate.status[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id         = data.aws_route53_zone.status[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "status" {
  count = local.status_auto_create_acm ? 1 : 0

  certificate_arn         = aws_acm_certificate.status[0].arn
  validation_record_fqdns = [for record in aws_route53_record.status_cert_validation : record.fqdn]
}

resource "aws_route53_record" "status_alias" {
  count = local.effective_status_domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.status[0].zone_id
  name    = local.effective_status_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.events.dns_name
    zone_id                = aws_lb.events.zone_id
    evaluate_target_health = true
  }
}
