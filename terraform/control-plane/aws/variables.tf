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

variable "node_stale_ttl" {
  description = "Freshness threshold used by the controller and visibility API."
  type        = string
  default     = "45s"
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

variable "api_listen_addr" {
  description = "Listen address for the read-only API role inside the container."
  type        = string
  default     = ":9445"
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

variable "status_acm_certificate_arn" {
  description = "Optional ACM certificate ARN covering the status UI/API hostname. If empty, a certificate is created for the effective status domain."
  type        = string
  default     = ""
}

variable "status_domain_name" {
  description = "Optional FQDN for the status UI/API (for example status.example.com). If empty, Terraform replaces the first label of events_domain_name with status."
  type        = string
  default     = ""
}

variable "status_hosted_zone_name" {
  description = "Optional Route53 hosted zone name used for status_domain_name DNS records. If empty, Terraform derives it by stripping the first label from the effective status domain."
  type        = string
  default     = ""
}

variable "service_ingress_domain" {
  description = "Deployment-owned DNS suffix used by the status API/UI to resolve service metadata.subdomain into https://<subdomain>.<service_ingress_domain>. Must match the data-plane domain_name. Leave empty only when services use exact metadata.host values or have no public routes."
  type        = string
  default     = ""

  validation {
    condition     = var.service_ingress_domain == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.service_ingress_domain))
    error_message = "service_ingress_domain must be empty or a canonical lowercase multi-label DNS name (for example example.com) with no trailing dot, scheme, port, path, or wildcard."
  }

  validation {
    condition     = length(var.service_ingress_domain) <= 253
    error_message = "service_ingress_domain must be at most 253 characters."
  }
}

variable "controlplane_image" {
  description = "OCI image URL for firework-controlplane (for example ghcr.io/org/firework-controlplane:tag)."
  type        = string
}

variable "controlplane_deployment_revision" {
  description = "Opaque revision changed to redeploy ECS services when controlplane_image uses a mutable tag. Set this to the published image digest."
  type        = string
  default     = ""
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
  description = "When true, create demo Secrets Manager secrets for missing control-plane inputs (webhook secret, TLS certs/keys, registry CA, and bootstrap-token enrollment material)."
  type        = bool
  default     = true
}

variable "auto_generated_tls_validity_hours" {
  description = "Validity period (hours) for auto-generated demo TLS certificates."
  type        = number
  default     = 8760
}

variable "controlplane_service_mode" {
  description = "Control-plane ECS layout. 'all' runs every role in one service (the demo default); 'split' preserves one service per role."
  type        = string
  default     = "all"

  validation {
    condition     = contains(["all", "split"], var.controlplane_service_mode)
    error_message = "controlplane_service_mode must be either \"all\" or \"split\"."
  }
}

variable "controlplane_desired_count" {
  description = "Desired task count for the combined all-role control-plane ECS service."
  type        = number
  default     = 1
}

variable "controlplane_task_cpu" {
  description = "CPU units for tasks in the combined all-role control-plane ECS service."
  type        = number
  default     = 1024
}

variable "controlplane_task_memory" {
  description = "Memory (MiB) for tasks in the combined all-role control-plane ECS service."
  type        = number
  default     = 2048
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

variable "api_desired_count" {
  description = "Desired task count for the read-only API ECS service."
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

variable "api_task_cpu" {
  description = "CPU units for read-only API tasks."
  type        = number
  default     = 256
}

variable "api_task_memory" {
  description = "Memory (MiB) for read-only API tasks."
  type        = number
  default     = 512
}

variable "github_webhook_secret_secret_arn" {
  description = "Optional Secrets Manager ARN containing the GitHub webhook secret value. If empty and auto_create_demo_secrets=true, one is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "operator_token_secret_arn" {
  description = "Optional Secrets Manager ARN containing the dedicated read-only operator token. If empty and auto_create_demo_secrets=true, one is generated."
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
  description = "Optional Secrets Manager ARN containing enrollment CA certificate PEM (required for bootstrap-token enrollment; auto-generated when missing and auto_create_demo_secrets=true)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_enrollment_ca_key_secret_arn" {
  description = "Optional Secrets Manager ARN containing enrollment CA private key PEM (required for bootstrap-token enrollment; auto-generated when missing and auto_create_demo_secrets=true)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_bootstrap_token_secret_arn" {
  description = "Optional Secrets Manager ARN containing bootstrap token used by nodes for first enrollment (auto-generated when missing and auto_create_demo_secrets=true)."
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
  description = "TTL for node certificates issued by the bootstrap-token enrollment CA."
  type        = string
  default     = "24h"
}

variable "registry_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to registry tasks."
  type        = list(string)
  default     = ["0.0.0.0/0"]
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

variable "api_task_port" {
  description = "Container port exposed by the read-only API role."
  type        = number
  default     = 9445
}
