output "delegated_subdomain" {
  value = aws_route53_record.gcp_delegation.fqdn
}
