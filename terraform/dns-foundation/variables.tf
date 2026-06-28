variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "parent_domain" {
  type        = string
  description = "Route53 parent hosted-zone domain, for example example.com"
}

variable "gcp_subdomain" {
  type        = string
  description = "Delegated GCP subdomain, for example gcp.example.com"
}

variable "gcp_dns_nameservers" {
  type        = list(string)
  description = "Exact nameservers returned by gcloud dns managed-zones describe"
  validation {
    condition     = length(var.gcp_dns_nameservers) == 4
    error_message = "Cloud DNS delegation must contain all four assigned nameservers."
  }
}
