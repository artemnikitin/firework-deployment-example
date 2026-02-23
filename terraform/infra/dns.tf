# -----------------------------------------------------------------------------
# DNS — Route53 alias records pointing to the ALB
# The hosted zone for var.domain_name is pre-existing and not managed here.
# -----------------------------------------------------------------------------

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Wildcard record — routes all *.domain_name traffic to the ALB.
# Traefik on each node uses the Host header to route to the correct tenant VM.
resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
