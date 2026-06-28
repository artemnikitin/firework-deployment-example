variable "gcp_project" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
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

variable "base_domain" {
  type        = string
  default     = ""
  description = "Optional base domain for the registry DNS A record (e.g. gcp.example.com). When set, creates registry.<base_domain> and outputs a DNS-based registry_url/registry_server_name instead of an IP-based one. The operator must provision the registry TLS cert with a DNS SAN matching registry.<base_domain>."
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique GCS bucket for Firework control-plane state/configs"
}

variable "state_bucket_force_destroy" {
  type        = bool
  description = "Allow `terraform destroy` to delete the state/config bucket even when it still contains objects (including noncurrent versions). Keep false in normal operation; set true only to tear the stack down."
  default     = false
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

variable "controlplane_image" {
  type        = string
  description = "Container image for firework-controlplane, e.g. ghcr.io/artemnikitin/firework-controlplane:v1.2.3"
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
  description = "Optional GitOps repository subdirectory used as the enricher input root. Empty (default) consumes the repository root. Routing is deployment-neutral via the agent ingress_domain."
}

variable "node_stale_ttl" {
  type    = string
  default = "45s"
}

variable "deployment_name" {
  type        = string
  default     = "firework"
  description = "Deployment scoping prefix for all resource names. Change this to run multiple deployments in the same GCP project without name collisions."
}

# --- Runtime configurability ---

variable "leader_lease_ttl" {
  type        = string
  default     = "30s"
  description = "Controller leader lease TTL."
}

variable "leader_renew_interval" {
  type        = string
  default     = "10s"
  description = "Controller leader lease renew interval."
}

variable "controller_tick" {
  type        = string
  default     = "10s"
  description = "Controller reconcile loop period."
}

variable "events_listen_addr" {
  type        = string
  default     = ":9444"
  description = "Listen address for the events role inside the container."
}

variable "registry_listen_addr" {
  type        = string
  default     = ":9443"
  description = "Listen address for the registry role inside the container."
}

variable "registry_node_cert_ttl" {
  type        = string
  default     = "24h"
  description = "TTL for node certificates issued by the enrollment CA."
}

variable "events_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the events Deployment."
}

variable "registry_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the registry Deployment."
}

variable "controller_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the controller Deployment."
}

variable "reconcile_on_start" {
  type        = bool
  default     = false
  description = "When true, the events role performs an immediate Git reconciliation on process start without waiting for a webhook."

  validation {
    condition     = !var.reconcile_on_start || var.git_repo_url != ""
    error_message = "git_repo_url is required when reconcile_on_start is true."
  }
}

# --- Secret bootstrap ---

variable "auto_create_demo_secrets" {
  type        = bool
  default     = true
  description = "When true, Terraform auto-generates TLS certs, enrollment CA, and bootstrap token and stores them in Secret Manager. Set to false and supply all *_secret_id vars to bring your own."
}

variable "auto_generated_tls_validity_hours" {
  type        = number
  default     = 8760
  description = "Validity period (hours) for auto-generated TLS certs and CA. Default is 1 year."
}

# --- Secret Manager secret IDs ---
# webhook_secret_id is always operator-provided (you configure the same value in GitHub).
# All others default to "" and are auto-generated when auto_create_demo_secrets = true.

variable "webhook_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the GitHub webhook secret value. Always operator-provided."
}

variable "bootstrap_token_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the node bootstrap token. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "events_tls_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the events server TLS cert PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "events_tls_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the events server TLS private key PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "registry_tls_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the registry server TLS cert PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "registry_tls_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the registry server TLS private key PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "enrollment_ca_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the enrollment CA cert PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "enrollment_ca_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the enrollment CA private key PEM. Auto-generated when empty and auto_create_demo_secrets = true."
}

variable "github_token_secret_id" {
  type        = string
  default     = ""
  description = "Optional Secret Manager secret ID containing a GitHub token for private GitOps repos. When set, GITHUB_TOKEN is injected into the events pod."
}

# --- Network exposure ---

variable "events_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDRs allowed to reach the events webhook load balancer."
}

variable "registry_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDRs allowed to reach the registry load balancer."
}
