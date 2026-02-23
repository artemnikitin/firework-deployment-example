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
  description = "Name/ID of the S3 configs bucket (created by the control-plane stack)"
  type        = string
}

variable "s3_configs_bucket_arn" {
  description = "ARN of the S3 configs bucket (created by the control-plane stack)"
  type        = string
}

variable "s3_images_bucket_id" {
  description = "Name/ID of the pre-existing S3 images bucket (managed by CI, not Terraform)"
  type        = string
}

variable "s3_images_bucket_arn" {
  description = "ARN of the pre-existing S3 images bucket (managed by CI, not Terraform)"
  type        = string
}

# --- EC2 / Nodes ---

variable "node_instance_type" {
  description = "EC2 instance type for Firecracker nodes (must support bare-metal KVM)"
  type        = string
  default     = "c6g.metal"
}

variable "node_ami_id" {
  description = "AMI ID for the Firecracker nodes (built by Packer)"
  type        = string
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
