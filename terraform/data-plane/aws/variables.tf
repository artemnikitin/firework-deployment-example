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
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1c"]
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
  description = "EC2 instance type for Firecracker nodes (must support bare-metal KVM)"
  type        = string
  default     = "c6g.metal"
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
  description = "Architecture filter used when resolving AMI by name pattern."
  type        = string
  default     = "arm64"

  validation {
    condition     = var.node_ami_architecture != ""
    error_message = "node_ami_architecture must be non-empty (for example arm64)."
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
  description = "Root domain name for DNS records (Route53 hosted zone must pre-exist)"
  type        = string
  default     = "xyz.com"
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
