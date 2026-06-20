variable "gcp_project" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "dns_zone_name" {
  type    = string
  default = "firework-gcp"
}

variable "base_domain" {
  type        = string
  description = "Tenant wildcard base domain, for example gcp.example.com. Single source of truth for wildcard DNS, the Certificate Manager wildcard certificate, and the agent ingress_domain. Routes resolve as <subdomain>.<base_domain>. Must be a canonical lowercase, multi-label DNS name with no trailing dot, scheme, port, path, or wildcard."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.base_domain))
    error_message = "base_domain must be a canonical lowercase multi-label DNS name (e.g. gcp.example.com) with no trailing dot, scheme, port, path, or wildcard."
  }

  validation {
    condition     = length(var.base_domain) <= 253
    error_message = "base_domain must be at most 253 characters."
  }
}

variable "network_cidr" {
  type    = string
  default = "10.30.0.0/24"
}

variable "node_machine_type" {
  type        = string
  default     = "n2-standard-8"
  description = "Intel-backed type that supports nested virtualization; E2, AMD *D, ARM, memory-optimized, and H4D are unsupported"
}

variable "node_count" {
  type        = number
  default     = 3
  description = "Six demo services request 18 vCPUs; three n2-standard-8 nodes provide 24 vCPUs"
  validation {
    condition     = var.node_count >= 3
    error_message = "node_count must be at least 3 for the demo workload."
  }
}

variable "node_image_family" {
  type    = string
  default = "firework-node-gcp"
}

variable "node_image_project" {
  type        = string
  default     = ""
  description = "Project containing the Packer image; defaults to gcp_project"
}

variable "config_bucket_name" {
  type = string
}

variable "config_prefix" {
  type    = string
  default = "cp/v1/"
  validation {
    condition     = endswith(var.config_prefix, "/")
    error_message = "config_prefix must end with '/'."
  }
}

variable "images_bucket_name" {
  type        = string
  description = "Globally unique amd64 images bucket name"
}

variable "registry_url" {
  type = string
}

variable "registry_server_name" {
  type = string
}

variable "registry_ca_secret_id" {
  type = string
}

variable "registry_bootstrap_token_secret_id" {
  type = string
}

variable "vm_subnet" {
  type    = string
  default = "172.16.0.0/24"
}

variable "vm_gateway" {
  type    = string
  default = "172.16.0.1"
}
