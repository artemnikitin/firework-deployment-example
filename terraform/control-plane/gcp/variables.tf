variable "gcp_project" {
  type        = string
  description = "GCP project ID"
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
  type        = string
  description = "Pre-existing Cloud DNS managed zone name"
  default     = "firework-gcp"
}

variable "events_domain" {
  type        = string
  description = "Public events webhook hostname"
}

variable "acme_email" {
  type        = string
  description = "Email used for Let's Encrypt registration"
}

variable "acme_server_url" {
  type    = string
  default = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique GCS bucket for Firework control-plane state/configs"
}

variable "state_prefix" {
  type    = string
  default = "cp/v1"
  validation {
    condition     = trim(var.state_prefix, "/") != ""
    error_message = "state_prefix must not be empty."
  }
}

variable "network_cidr" {
  type    = string
  default = "10.20.0.0/24"
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "firework_controlplane_path" {
  type        = string
  description = "Path to a locally built linux/amd64 firework-controlplane binary uploaded to GCS by Terraform"
}

variable "git_repo_url" {
  type        = string
  description = "GitOps repository cloned by the events role"
}

variable "target_branch" {
  type    = string
  default = "main"
}

variable "config_dir" {
  type        = string
  default     = ""
  description = "Optional GitOps repository subdirectory used as the enricher input root. Empty (default) consumes the repository root. GCP no longer uses a provider-specific hostname overlay directory; routing is deployment-neutral via the agent ingress_domain."
}

variable "node_stale_ttl" {
  type    = string
  default = "45s"
}
