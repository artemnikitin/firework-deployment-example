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
  description = "CIDR block for the control-plane VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for ECS services and load balancers."
  type        = list(string)
  default     = ["10.50.0.0/24", "10.50.1.0/24"]
}

variable "availability_zones" {
  description = "Availability zones used for the public subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "assign_public_ip" {
  description = "Assign public IPs to ECS tasks. Keep true unless NAT is configured."
  type        = bool
  default     = true
}

variable "state_prefix" {
  description = "S3 prefix for control-plane state and rendered configs."
  type        = string
  default     = "cp/v1"
}

variable "state_s3_endpoint_url" {
  description = "Optional custom S3 endpoint URL (for LocalStack/MinIO)."
  type        = string
  default     = ""
}

variable "state_s3_force_path_style" {
  description = "Enable path-style S3 requests (required for some custom endpoints)."
  type        = bool
  default     = false
}

variable "target_branch" {
  description = "Git branch that events role accepts from GitHub webhooks."
  type        = string
  default     = "main"
}

variable "config_dir" {
  description = "Optional subdirectory in the cloned Git repo that contains Firework configs."
  type        = string
  default     = ""
}

variable "git_repo_url" {
  description = "Git repo URL used for startup reconciliation when reconcile_on_start is enabled."
  type        = string
  default     = ""
}

variable "reconcile_on_start" {
  description = "When true, events role performs an immediate Git reconciliation on startup using git_repo_url."
  type        = bool
  default     = false
}

variable "leader_lease_ttl" {
  description = "Controller leader lease TTL."
  type        = string
  default     = "30s"
}

variable "leader_renew_interval" {
  description = "Controller leader lease renew interval."
  type        = string
  default     = "10s"
}

variable "controller_tick" {
  description = "Controller reconcile loop period."
  type        = string
  default     = "10s"
}

variable "events_listen_addr" {
  description = "Listen address for the events role inside the container."
  type        = string
  default     = ":9444"
}

variable "registry_listen_addr" {
  description = "Listen address for the registry role inside the container."
  type        = string
  default     = ":9443"
}

variable "events_listener_port" {
  description = "Public HTTPS listener port for the events ALB."
  type        = number
  default     = 443
}

variable "registry_listener_port" {
  description = "TCP listener port for the registry NLB."
  type        = number
  default     = 9443
}

variable "registry_internal" {
  description = "Whether the registry NLB is internal-only."
  type        = bool
  default     = false
}

variable "events_acm_certificate_arn" {
  description = "Optional ACM certificate ARN used by the events HTTPS ALB listener. If empty, a certificate can be auto-created by setting events_domain_name."
  type        = string
  default     = ""
}

variable "events_domain_name" {
  description = "Optional FQDN for the events webhook endpoint (for example events.example.com). When set and events_acm_certificate_arn is empty, ACM certificate + DNS validation are created automatically."
  type        = string
  default     = ""
}

variable "events_hosted_zone_name" {
  description = "Optional Route53 hosted zone name used for events_domain_name DNS records (for example example.com). If empty, Terraform derives it by stripping the first label from events_domain_name."
  type        = string
  default     = ""
}

variable "controlplane_image" {
  description = "OCI image URL for firework-controlplane (for example ghcr.io/org/firework-controlplane:tag)."
  type        = string
}

variable "controlplane_binary_path" {
  description = "Path to firework-controlplane binary inside the container image."
  type        = string
  default     = "/usr/local/bin/firework-controlplane"
}

variable "controlplane_image_pull_secret_arn" {
  description = "Optional Secrets Manager ARN for private registry credentials (repositoryCredentials)."
  type        = string
  default     = ""
}

variable "auto_create_demo_secrets" {
  description = "When true, create demo Secrets Manager secrets for missing control-plane inputs (webhook secret, TLS certs/keys, registry CA, and legacy enrollment material)."
  type        = bool
  default     = true
}

variable "auto_generated_tls_validity_hours" {
  description = "Validity period (hours) for auto-generated demo TLS certificates."
  type        = number
  default     = 8760
}

variable "events_desired_count" {
  description = "Desired task count for the events ECS service."
  type        = number
  default     = 2
}

variable "registry_desired_count" {
  description = "Desired task count for the registry ECS service."
  type        = number
  default     = 2
}

variable "controller_desired_count" {
  description = "Desired task count for the controller ECS service."
  type        = number
  default     = 2
}

variable "events_task_cpu" {
  description = "CPU units for events tasks."
  type        = number
  default     = 256
}

variable "events_task_memory" {
  description = "Memory (MiB) for events tasks."
  type        = number
  default     = 512
}

variable "registry_task_cpu" {
  description = "CPU units for registry tasks."
  type        = number
  default     = 256
}

variable "registry_task_memory" {
  description = "Memory (MiB) for registry tasks."
  type        = number
  default     = 512
}

variable "controller_task_cpu" {
  description = "CPU units for controller tasks."
  type        = number
  default     = 256
}

variable "controller_task_memory" {
  description = "Memory (MiB) for controller tasks."
  type        = number
  default     = 512
}

variable "github_webhook_secret_secret_arn" {
  description = "Optional Secrets Manager ARN containing the GitHub webhook secret value. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_token_secret_arn" {
  description = "Optional Secrets Manager ARN containing a GitHub token for cloning private repos."
  type        = string
  sensitive   = true
  default     = ""
}

variable "events_tls_cert_secret_arn" {
  description = "Optional Secrets Manager ARN containing PEM certificate for events role TLS. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "events_tls_key_secret_arn" {
  description = "Optional Secrets Manager ARN containing PEM private key for events role TLS. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_tls_cert_secret_arn" {
  description = "Optional Secrets Manager ARN containing PEM certificate for registry role TLS. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_tls_key_secret_arn" {
  description = "Optional Secrets Manager ARN containing PEM private key for registry role TLS. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_client_ca_secret_arn" {
  description = "Optional Secrets Manager ARN containing the registry trust root CA PEM used to validate node client certs. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_enrollment_ca_secret_arn" {
  description = "Optional Secrets Manager ARN containing enrollment CA certificate PEM (required for legacy bootstrap-token enrollment; auto-generated when missing and auto_create_demo_secrets=true)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_enrollment_ca_key_secret_arn" {
  description = "Optional Secrets Manager ARN containing enrollment CA private key PEM (required for legacy bootstrap-token enrollment; auto-generated when missing and auto_create_demo_secrets=true)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_bootstrap_token_secret_arn" {
  description = "Optional Secrets Manager ARN containing bootstrap token used by nodes for first enrollment (legacy mode; auto-generated when missing and auto_create_demo_secrets=true)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_bootstrap_node_id" {
  description = "Optional node_id restriction bound to the bootstrap token. Empty means any node_id."
  type        = string
  default     = ""
}

variable "registry_node_cert_ttl" {
  description = "TTL for node certificates issued by enrollment CA."
  type        = string
  default     = "24h"
}

variable "registry_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to registry tasks."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_step_ca" {
  description = "When true, deploy an additional step-ca PKI service on ECS/Fargate."
  type        = bool
  default     = false
}

variable "step_ca_image" {
  description = "Container image for step-ca (for example smallstep/step-ca:latest)."
  type        = string
  default     = "smallstep/step-ca:latest"
}

variable "step_ca_image_pull_secret_arn" {
  description = "Optional Secrets Manager ARN for private registry credentials used by the step-ca image."
  type        = string
  default     = ""
}

variable "step_ca_password_secret_arn" {
  description = "Optional Secrets Manager ARN containing the step-ca password used to encrypt/decrypt CA keys. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "step_ca_internal" {
  description = "Whether the step-ca NLB is internal-only."
  type        = bool
  default     = false
}

variable "step_ca_listener_port" {
  description = "TCP listener port for the step-ca NLB."
  type        = number
  default     = 9000
}

variable "step_ca_task_port" {
  description = "Container port exposed by the step-ca task."
  type        = number
  default     = 9000
}

variable "step_ca_listen_addr" {
  description = "Listen address for step-ca inside the container."
  type        = string
  default     = ":9000"
}

variable "step_ca_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to the step-ca task."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "step_ca_desired_count" {
  description = "Desired task count for the step-ca ECS service. Keep this at 1; step-ca state is single-writer in this setup."
  type        = number
  default     = 1

  validation {
    condition     = var.step_ca_desired_count >= 0 && var.step_ca_desired_count <= 1
    error_message = "step_ca_desired_count must be 0 or 1 in this deployment."
  }
}

variable "step_ca_task_cpu" {
  description = "CPU units for step-ca tasks."
  type        = number
  default     = 256
}

variable "step_ca_task_memory" {
  description = "Memory (MiB) for step-ca tasks."
  type        = number
  default     = 512
}

variable "step_ca_name" {
  description = "Display name used when initializing step-ca."
  type        = string
  default     = "Firework Step CA"
}

variable "step_ca_bootstrap_provisioner_name" {
  description = "Initial local admin provisioner name used to bootstrap step-ca config."
  type        = string
  default     = "bootstrap-admin"
}

variable "step_ca_aws_provisioner_name" {
  description = "AWS IID provisioner name added to step-ca."
  type        = string
  default     = "aws-iid"
}

variable "step_ca_aws_account_ids" {
  description = "AWS account IDs allowed by the step-ca AWS IID provisioner. Empty means current account only."
  type        = list(string)
  default     = []
}

variable "step_ca_cert_ttl" {
  description = "Default and max certificate TTL configured on the step-ca AWS IID provisioner."
  type        = string
  default     = "24h"
}

variable "step_ca_provisioner_disable_custom_sans" {
  description = "Disable custom SANs in the step-ca AWS IID provisioner."
  type        = bool
  default     = false
}

variable "step_ca_provisioner_disable_trust_on_first_use" {
  description = "Disable trust-on-first-use in the step-ca AWS IID provisioner."
  type        = bool
  default     = false
}

variable "step_ca_additional_dns_names" {
  description = "Additional DNS names added to the step-ca server certificate at initialization."
  type        = list(string)
  default     = []
}

variable "step_ca_root_ca_secret_arn" {
  description = "Optional Secrets Manager ARN containing the step-ca root CA certificate PEM for node bootstrap."
  type        = string
  sensitive   = true
  default     = ""
}

# --- Observability ---

variable "observability_log_retention_days" {
  description = "Retention (days) for CloudWatch log groups managed by this stack."
  type        = number
  default     = 14
}

variable "events_health_check_path" {
  description = "Health check path for events target group."
  type        = string
  default     = "/healthz"
}

variable "events_health_check_matcher" {
  description = "Expected HTTP status matcher for events health checks."
  type        = string
  default     = "200-399"
}

variable "events_task_port" {
  description = "Container port exposed by events role."
  type        = number
  default     = 9444
}

variable "registry_task_port" {
  description = "Container port exposed by registry role."
  type        = number
  default     = 9443
}
