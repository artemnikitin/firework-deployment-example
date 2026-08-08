variable "gcp_project" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "deployment_name" {
  type        = string
  default     = "firework"
  description = "Deployment scoping prefix for all resource names. Must match the control-plane stack's deployment_name."
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
  default     = "n4-standard-8"
  description = "Intel N4 default with nested virtualization. N4 needs Hyperdisk and gVNIC and uses NVMe automatically; E2, AMD *D, ARM, memory-optimized, and H4D are unsupported."
}

variable "node_count" {
  type        = number
  default     = 3
  description = "Six demo services request 18 vCPUs; three n4-standard-8 nodes provide 24 vCPUs"
  validation {
    condition     = var.node_count >= 3
    error_message = "node_count must be at least 3 for the demo workload."
  }
}

# --- Persistent storage (disabled by default) ---

variable "enable_local_storage" {
  type        = bool
  default     = false
  description = "Attach one stateful Hyperdisk Balanced data disk to every MIG instance for Firework local volumes."
}

variable "local_storage_size_gib" {
  type        = number
  default     = 500
  description = "Physical Hyperdisk size per node in GiB."

  validation {
    condition     = var.local_storage_size_gib >= 10
    error_message = "local_storage_size_gib must be at least 10 GiB."
  }
}

variable "local_storage_capacity" {
  type        = string
  default     = "450Gi"
  description = "Firework logical admission budget rendered to storage.local.capacity."

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.local_storage_capacity))
    error_message = "local_storage_capacity must be a positive integer followed by Mi, Gi, or Ti."
  }
}

variable "enable_shared_storage" {
  type        = bool
  default     = false
  description = "Provision Regional Filestore with NFSv4.1 and mount it on every node."
}

variable "shared_storage_backend_id" {
  type        = string
  default     = "primary"
  description = "Stable deployment-wide identity written to the shared root and rendered to Firework."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.shared_storage_backend_id))
    error_message = "shared_storage_backend_id must be a lowercase DNS-label-like value."
  }
}

variable "shared_storage_capacity" {
  type        = string
  default     = "900Gi"
  description = "Aggregate Firework admission budget. Keep below Filestore provisioned capacity."

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.shared_storage_capacity))
    error_message = "shared_storage_capacity must be a positive integer followed by Mi, Gi, or Ti."
  }
}

variable "filestore_tier" {
  type        = string
  default     = "REGIONAL"
  description = "Filestore tier supporting NFSv4.1."

  validation {
    condition     = contains(["REGIONAL", "ENTERPRISE", "ZONAL", "HIGH_SCALE_SSD"], var.filestore_tier)
    error_message = "filestore_tier must support NFSv4.1."
  }
}

variable "filestore_capacity_gib" {
  type        = number
  default     = 1024
  description = "Provisioned Filestore capacity in GiB. Tier/region minimums still apply."

  validation {
    condition     = var.filestore_capacity_gib >= 100
    error_message = "filestore_capacity_gib must be at least 100 GiB; verify the selected tier's regional minimum."
  }
}

variable "filestore_deletion_protection" {
  type        = bool
  default     = true
  description = "Protect retained shared data from Terraform deletion. Disable only for deliberate teardown after backups."
}

variable "node_zones" {
  type        = list(string)
  default     = null
  description = <<-EOT
    Optional regional-MIG zone placement override. Any two or more distinct
    zones of gcp_region are accepted, in any order. Leave null to use every
    zone the region currently reports as UP, which is discovered rather than
    assumed because not all regions have a "-a" zone. Independent of
    node_count: the regional MIG spreads whatever target size you ask for
    across these zones.
  EOT

  validation {
    condition     = var.node_zones == null || length(distinct(var.node_zones)) >= 2
    error_message = "node_zones must contain at least two distinct zones."
  }

  validation {
    condition     = var.node_zones == null || length(distinct(var.node_zones)) == length(var.node_zones)
    error_message = "node_zones must not contain duplicates."
  }

  validation {
    condition     = var.node_zones == null || alltrue([for z in var.node_zones : startswith(z, "${var.gcp_region}-")])
    error_message = "Every node_zones entry must be a zone of gcp_region."
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

variable "use_control_plane_remote_state" {
  type        = bool
  default     = true
  description = "When true, auto-wire config_bucket_name, registry_url, and secret IDs from the control-plane Terraform state file."
}

variable "control_plane_state_path" {
  type        = string
  default     = "../../control-plane/gcp/terraform.tfstate"
  description = "Path to the control-plane terraform.tfstate (absolute or relative to this module). Used when use_control_plane_remote_state is true."
}

variable "config_bucket_name" {
  type        = string
  default     = ""
  description = "GCS bucket for Firework control-plane config. Auto-filled from control-plane state when use_control_plane_remote_state is true."
}

variable "config_prefix" {
  type    = string
  default = "cp/v1/"
  validation {
    condition     = var.config_prefix == "" || endswith(var.config_prefix, "/")
    error_message = "config_prefix must end with '/'."
  }
}

variable "images_bucket_name" {
  type        = string
  description = "Globally unique images bucket name (created by the images-infra stack). Holds every architecture under an <arch>/ key prefix."
}

variable "registry_url" {
  type        = string
  default     = ""
  description = "Firework registry HTTPS URL. Auto-filled from control-plane state when use_control_plane_remote_state is true."
}

variable "registry_server_name" {
  type        = string
  default     = ""
  description = "TLS server name for the registry. Auto-filled from control-plane state when use_control_plane_remote_state is true."
}

variable "registry_ca_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the enrollment CA cert. Auto-filled from control-plane state when use_control_plane_remote_state is true."
}

variable "registry_bootstrap_token_secret_id" {
  type        = string
  default     = ""
  description = "Secret Manager secret ID for the node bootstrap token. Auto-filled from control-plane state when use_control_plane_remote_state is true."
}

variable "vm_subnet" {
  type    = string
  default = "172.16.0.0/24"
}

variable "vm_gateway" {
  type    = string
  default = "172.16.0.1"
}

variable "observability_log_retention_days" {
  type        = number
  default     = 30
  description = "Days before log archives (node logs and LB access logs) are deleted."
}
