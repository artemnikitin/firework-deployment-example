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

variable "status_domain" {
  type        = string
  default     = ""
  description = "Public status UI/API hostname. Auto-filled from durable Events edge state when empty."
}

variable "use_events_edge_remote_state" {
  type        = bool
  default     = true
  description = "Read the durable Events edge outputs from local Terraform state."
}

variable "events_edge_state_path" {
  type        = string
  default     = "../../events-edge/gcp/terraform.tfstate"
  description = "Path to the durable Events edge terraform.tfstate (absolute or relative to this module)."
}

variable "events_gateway_address_name" {
  type        = string
  default     = ""
  description = "Reserved global address name for the Events Gateway. Auto-filled from Events edge state when enabled."
}

variable "events_certificate_map_name" {
  type        = string
  default     = ""
  description = "Certificate Manager map name for the Events Gateway. Auto-filled from Events edge state when enabled."
}

variable "base_domain" {
  type        = string
  default     = ""
  description = "Optional base domain for the registry DNS A record (e.g. gcp.example.com). When set, creates registry.<base_domain> and outputs a DNS-based registry_url/registry_server_name instead of an IP-based one. The operator must provision the registry TLS cert with a DNS SAN matching registry.<base_domain>."
}

variable "service_ingress_domain" {
  type        = string
  default     = ""
  description = "Deployment-owned DNS suffix used by the status API/UI to resolve service metadata.subdomain into https://<subdomain>.<service_ingress_domain>. Must match the data-plane base_domain. Leave empty only when services use exact metadata.host values or have no public routes."

  validation {
    condition     = var.service_ingress_domain == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.service_ingress_domain))
    error_message = "service_ingress_domain must be empty or a canonical lowercase multi-label DNS name (for example gcp.example.com) with no trailing dot, scheme, port, path, or wildcard."
  }

  validation {
    condition     = length(var.service_ingress_domain) <= 253
    error_message = "service_ingress_domain must be at most 253 characters."
  }
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
  description = "OCI image URL for firework-controlplane (for example ghcr.io/org/firework-controlplane:tag)."
}

variable "controlplane_deployment_revision" {
  type        = string
  default     = ""
  description = "Opaque revision changed to roll the GKE control-plane workload when controlplane_image uses a mutable tag. Set this to the published image digest."
}

variable "controlplane_service_mode" {
  type        = string
  default     = "all"
  description = "Control-plane GKE layout. 'all' runs every role in one Deployment (the demo default); 'split' preserves one Deployment per role."

  validation {
    condition     = contains(["all", "split"], var.controlplane_service_mode)
    error_message = "controlplane_service_mode must be either \"all\" or \"split\"."
  }
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

variable "events_port" {
  type        = number
  default     = 9444
  description = "HTTPS port for the events role and its GKE Service backend."

  validation {
    condition     = var.events_port > 0 && var.events_port < 65536
    error_message = "events_port must be a valid TCP port."
  }
}

variable "registry_port" {
  type        = number
  default     = 9443
  description = "HTTPS port for the registry role and its internal load balancer."

  validation {
    condition     = var.registry_port > 0 && var.registry_port < 65536
    error_message = "registry_port must be a valid TCP port."
  }
}

variable "api_port" {
  type        = number
  default     = 9445
  description = "HTTPS port for the read-only API role and its GKE Service backend."

  validation {
    condition     = var.api_port > 0 && var.api_port < 65536
    error_message = "api_port must be a valid TCP port."
  }

  validation {
    condition     = length(distinct([var.events_port, var.registry_port, var.api_port])) == 3
    error_message = "events_port, registry_port, and api_port must be distinct because the combined control-plane process binds all three listeners."
  }
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

variable "api_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the read-only API Deployment."
}

variable "controlplane_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the combined all-role control-plane Deployment."
}

variable "controlplane_cpu_request" {
  type        = string
  default     = "1000m"
  description = "CPU request for each replica of the combined all-role control-plane Deployment."
}

variable "controlplane_memory_request" {
  type        = string
  default     = "2Gi"
  description = "Memory request for each replica of the combined all-role control-plane Deployment."
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
  description = "When true, Terraform generates all TLS/PKI material and the bootstrap token. When false, supply every *_secret_id variable to bring your own. Partial overrides are intentionally rejected."

  validation {
    condition = var.auto_create_demo_secrets ? alltrue([
      var.bootstrap_token_secret_id == "",
      var.events_tls_cert_secret_id == "",
      var.events_tls_key_secret_id == "",
      var.controlplane_service_mode == "all" || var.registry_tls_cert_secret_id == "",
      var.controlplane_service_mode == "all" || var.registry_tls_key_secret_id == "",
      var.enrollment_ca_cert_secret_id == "",
      var.enrollment_ca_key_secret_id == "",
      var.operator_token_secret_id == "",
      ]) : alltrue([
      var.bootstrap_token_secret_id != "",
      var.events_tls_cert_secret_id != "",
      var.events_tls_key_secret_id != "",
      var.controlplane_service_mode == "all" || var.registry_tls_cert_secret_id != "",
      var.controlplane_service_mode == "all" || var.registry_tls_key_secret_id != "",
      var.enrollment_ca_cert_secret_id != "",
      var.enrollment_ca_key_secret_id != "",
      var.operator_token_secret_id != "",
    ])
    error_message = "Use either fully auto-generated TLS/PKI/operator material or provide every TLS, enrollment CA, bootstrap-token, and operator-token secret ID; partial overrides are unsupported."
  }
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
  description = "Secret Manager secret ID for the node bootstrap token. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "events_tls_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the events server TLS cert PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "events_tls_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the events server TLS private key PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "registry_tls_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the registry server TLS cert PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "registry_tls_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the registry server TLS private key PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "enrollment_ca_cert_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the enrollment CA cert PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "enrollment_ca_key_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the enrollment CA private key PEM. Required with every other PKI secret ID when auto_create_demo_secrets is false."
}

variable "github_token_secret_id" {
  type        = string
  default     = ""
  description = "Optional Secret Manager secret ID containing a GitHub token for private GitOps repos. When set, GITHUB_TOKEN is injected into the events pod."
}

variable "operator_token_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the dedicated read-only operator token. Auto-generated in demo mode."
}

# --- Network exposure ---

variable "registry_allowed_cidrs" {
  type        = list(string)
  default     = ["10.30.0.0/24"]
  description = "Source CIDRs allowed to reach the internal registry load balancer. Keep this aligned with the data-plane network CIDR."
}
