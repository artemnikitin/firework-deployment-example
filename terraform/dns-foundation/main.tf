data "aws_route53_zone" "parent" {
  name         = trimsuffix(var.parent_domain, ".")
  private_zone = false
}

resource "aws_route53_record" "gcp_delegation" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = trimsuffix(var.gcp_subdomain, ".")
  type    = "NS"
  ttl     = 300
  records = var.gcp_dns_nameservers

  lifecycle {
    prevent_destroy = true
  }
}
