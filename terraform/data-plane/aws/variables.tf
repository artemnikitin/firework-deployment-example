variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "firework-example"
}

variable "use_control_plane_remote_state" {
  description = "When true, read control-plane outputs from a local terraform.tfstate file and auto-wire data-plane inputs."
  type        = bool
  default     = true
}

variable "control_plane_state_path" {
  description = "Path to control-plane terraform state file used for auto-wiring (relative to this stack when using local backend)."
  type        = string
  default     = "../../control-plane/aws/terraform.tfstate"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = <<-EOT
    Availability zones to deploy into. Any number from 2 upwards works, in any
    order, and the list can be changed later: each AZ's subnet CIDR is derived
    from the AZ name, not from its position, so adding or removing a zone does
    not renumber the others. Independent of node_count — the Auto Scaling Group
    spreads whatever number of nodes you ask for across these zones.
  EOT
  type        = list(string)
  default     = ["us-east-1a", "us-east-1c"]

  validation {
    # An Application Load Balancer requires subnets in at least two zones, and
    # the ALB lives in these subnets. This is an AWS constraint, not a limit of
    # this stack.
    condition     = length(var.availability_zones) >= 2
    error_message = "availability_zones must contain at least 2 zones: the ALB requires subnets in two availability zones."
  }

  validation {
    condition     = length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must not contain duplicates."
  }

  validation {
    # Subnet CIDRs are derived from the trailing zone letter, so names must be
    # of the standard <region><letter> form with a letter in a-h. Local Zone and
    # Wavelength names (for example us-east-1-bos-1a) are not supported here.
    condition     = alltrue([for az in var.availability_zones : can(regex("^[a-z]{2}-[a-z]+-[0-9][a-h]$", az))])
    error_message = "Each availability_zones entry must look like us-east-1a, with a trailing zone letter in the range a-h. Local Zone and Wavelength zone names are not supported."
  }
}

variable "node_network_placement" {
  description = <<-EOT
    Where Firecracker nodes are placed. "public" (default) puts nodes in the
    public subnets with a public IP and internet gateway egress, creating no NAT
    gateways — the cheapest option at demo scale. "private" keeps nodes in
    private subnets behind NAT gateways. See the data-plane README for the
    security trade-offs of "public", in particular that source/destination check
    is disabled on these nodes.
  EOT
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.node_network_placement)
    error_message = "node_network_placement must be either \"public\" or \"private\"."
  }
}

variable "nat_gateway_mode" {
  description = <<-EOT
    NAT gateway topology when node_network_placement = "private". "per_az"
    (default) creates one gateway per availability zone and keeps node egress
    alive through a single-AZ failure. "single" creates one gateway for all
    private subnets, which is cheaper but introduces an AZ dependency and
    cross-AZ data charges for non-S3 egress. Ignored in "public" placement.
  EOT
  type        = string
  default     = "per_az"

  validation {
    condition     = contains(["per_az", "single"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be either \"per_az\" or \"single\"."
  }
}

# --- S3 (pre-existing, managed outside this stack) ---

variable "s3_configs_bucket_id" {
  description = "Optional name/ID of the S3 configs bucket (created by control-plane). If empty, auto-wired from control-plane outputs when use_control_plane_remote_state=true."
  type        = string
  default     = ""
}

variable "s3_configs_bucket_arn" {
  description = "Optional ARN of the S3 configs bucket (created by control-plane). If empty, auto-wired from control-plane outputs when use_control_plane_remote_state=true."
  type        = string
  default     = ""
}

variable "s3_configs_prefix" {
  description = "Optional prefix in the configs bucket where rendered node configs live (for example cp/v1/). If empty, auto-wired from control-plane config_prefix."
  type        = string
  default     = ""

  validation {
    condition     = var.s3_configs_prefix == "" || endswith(var.s3_configs_prefix, "/")
    error_message = "s3_configs_prefix must end with '/' (for example cp/v1/)."
  }
}

variable "s3_images_bucket_id" {
  description = "Name/ID of the pre-existing S3 images bucket (managed by CI, not Terraform)"
  type        = string
}

variable "s3_images_bucket_arn" {
  description = "ARN of the pre-existing S3 images bucket (managed by CI, not Terraform)"
  type        = string
}

variable "registry_url" {
  description = "Optional public HTTPS URL of the control-plane registry endpoint. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "registry_server_name" {
  description = "Optional TLS server name override for registry certificate validation. If empty, derived from registry_url host."
  type        = string
  default     = ""
}

variable "registry_client_ca_secret_arn" {
  description = "Optional legacy fallback: Secrets Manager ARN containing the registry trust root CA PEM. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "registry_bootstrap_token_secret_arn" {
  description = "Optional legacy fallback: Secrets Manager ARN containing registry bootstrap token for first-time node enrollment. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "step_ca_url" {
  description = "Optional step-ca URL for node certificate bootstrap. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "step_ca_root_ca_secret_arn" {
  description = "Optional Secrets Manager ARN containing step-ca root CA PEM used by nodes. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "step_ca_provisioner" {
  description = "Optional step-ca provisioner name used by nodes when requesting certificates. If empty, auto-wired from control-plane outputs when available."
  type        = string
  default     = ""
}

variable "step_ca_subject_suffix" {
  description = "Suffix appended to the EC2 instance ID to form the node certificate subject."
  type        = string
  default     = ".node.firework.internal"
}

variable "step_ca_renew_expires_in" {
  description = "Time before certificate expiry when step CLI renew daemon starts attempting renewals."
  type        = string
  default     = "8h"
}

# --- EC2 / Nodes ---

variable "node_instance_type" {
  description = <<-EOT
    EC2 instance type for Firecracker nodes. Must expose /dev/kvm, which means
    either a bare-metal instance or a virtual instance type that supports nested
    virtualization (see node_nested_virtualization). The default is a virtual
    x86_64 instance because bare metal forces a 64 vCPU purchase and costs
    roughly six times more per hour for this demo.
  EOT
  type        = string
  default     = "c8i.2xlarge"
}

variable "node_nested_virtualization" {
  description = <<-EOT
    Enable the nested virtualization CPU option so a virtual (non-bare-metal)
    instance exposes /dev/kvm to Firecracker. Required for the default
    node_instance_type. Set to false when node_instance_type is a bare-metal
    type such as c6g.metal, which exposes /dev/kvm natively and rejects this
    option. Supported on Intel families only (C8i, M8i, R8i and their id/flex
    variants, X8i, C7i, M7i, R7i, C7i-flex, M7i-flex, I7i) — not on Graviton.
  EOT
  type        = bool
  default     = true
}

variable "node_ami_id" {
  description = "Optional explicit AMI ID for Firecracker nodes. When empty, AMI can be resolved from node_ami_name_pattern or packer manifest."
  type        = string
  default     = ""
}

variable "node_ami_name_pattern" {
  description = "Optional AMI name pattern used to discover the latest matching image in aws_region. If no wildcard is provided, Terraform wraps it as *pattern*."
  type        = string
  default     = ""
}

variable "node_ami_owners" {
  description = "Owners used when resolving AMI by name pattern."
  type        = list(string)
  default     = ["self"]
}

variable "node_ami_architecture" {
  description = "Architecture filter used when resolving AMI by name pattern. Must match the architecture the node AMI was built for and the rootfs images in s3_images_bucket_id."
  type        = string
  default     = "x86_64"

  validation {
    condition     = var.node_ami_architecture != ""
    error_message = "node_ami_architecture must be non-empty (for example x86_64 or arm64)."
  }
}

variable "use_packer_manifest_ami" {
  description = "When true and node_ami_id/node_ami_name_pattern are empty, resolve AMI from the latest entry in packer manifest."
  type        = bool
  default     = true
}

variable "packer_manifest_path" {
  description = "Path to Packer manifest.json used for AMI auto-resolution (relative to this stack when not absolute)."
  type        = string
  default     = "../../../packer/aws/manifest.json"
}

variable "node_key_name" {
  description = "EC2 key pair name for SSH access to nodes"
  type        = string
}

variable "node_count" {
  description = "Number of Firecracker nodes"
  type        = number
  default     = 1
}


variable "node_volume_size" {
  description = "Root volume size in GB for each node"
  type        = number
  default     = 50
}

# --- Persistent storage (disabled by default) ---

variable "enable_local_storage" {
  description = "Attach one encrypted retained gp3 data disk to every node for Firework local volumes."
  type        = bool
  default     = false
}

variable "local_storage_size_gib" {
  description = "Physical gp3 data-disk size per node in GiB. Cloud disks are grown separately from application volume quotas."
  type        = number
  default     = 500

  validation {
    condition     = var.local_storage_size_gib >= 10
    error_message = "local_storage_size_gib must be at least 10 GiB."
  }
}

variable "local_storage_capacity" {
  description = "Firework logical admission budget rendered to storage.local.capacity. Keep below physical disk size."
  type        = string
  default     = "450Gi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.local_storage_capacity))
    error_message = "local_storage_capacity must be a positive integer followed by Mi, Gi, or Ti."
  }
}

variable "enable_shared_storage" {
  description = "Provision encrypted regional EFS and mount it on nodes. Firework shared runtime remains safety-gated until durable fencing is enabled."
  type        = bool
  default     = false
}

variable "shared_storage_backend_id" {
  description = "Stable deployment-wide identity written to the shared root and rendered to the agent."
  type        = string
  default     = "primary"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.shared_storage_backend_id))
    error_message = "shared_storage_backend_id must be a lowercase DNS-label-like value."
  }
}

variable "shared_storage_capacity" {
  description = "Optional aggregate Firework admission budget for EFS. Empty leaves aggregate admission unbounded."
  type        = string
  default     = ""

  validation {
    condition     = var.shared_storage_capacity == "" || can(regex("^[1-9][0-9]*(Mi|Gi|Ti)$", var.shared_storage_capacity))
    error_message = "shared_storage_capacity must be empty or a positive integer followed by Mi, Gi, or Ti."
  }
}

variable "shared_storage_use_access_point" {
  description = "Mount EFS through a dedicated Firework access point."
  type        = bool
  default     = true
}

# --- Networking (microVM guest) ---

variable "vm_subnet" {
  description = "CIDR subnet for microVM guest IPs (e.g. 172.16.0.0/24)"
  type        = string
  default     = "172.16.0.0/24"
}

variable "vm_gateway" {
  description = "Gateway IP for the microVM bridge (assigned to the host bridge device)"
  type        = string
  default     = "172.16.0.1"
}

# --- Traefik ---

variable "traefik_port" {
  description = "Port Traefik listens on for HTTP traffic (ALB → Traefik target group)"
  type        = number
  default     = 8080
}

# --- DNS ---

variable "domain_name" {
  description = "Root domain name for DNS records (Route53 hosted zone must pre-exist). Single source of truth for the wildcard ACM certificate and the agent ingress_domain; routes resolve as <subdomain>.<domain_name>. Must be a canonical lowercase, multi-label DNS name with no trailing dot, scheme, port, path, or wildcard."
  type        = string
  default     = "xyz.com"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a canonical lowercase multi-label DNS name (e.g. example.com) with no trailing dot, scheme, port, path, or wildcard."
  }

  validation {
    condition     = length(var.domain_name) <= 253
    error_message = "domain_name must be at most 253 characters."
  }
}

# --- ACM ---

variable "acm_create_certificate" {
  description = "When true, create and DNS-validate a new wildcard ACM certificate. Set to false to use a pre-existing certificate via acm_certificate_arn."
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "ARN of a pre-existing ACM certificate. Required when acm_create_certificate = false."
  type        = string
  default     = ""
}

# --- Observability ---

variable "observability_log_retention_days" {
  description = "Retention (days) for CloudWatch log groups managed by this stack."
  type        = number
  default     = 14
}

variable "alb_access_logs_retention_days" {
  description = "Retention (days) for ALB access logs stored in S3."
  type        = number
  default     = 30
}
