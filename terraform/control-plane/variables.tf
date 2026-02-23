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

# --- Lambda ---

variable "enricher_zip_path" {
  description = "Local path to a pre-built enricher ZIP. If empty, the release is downloaded from GitHub."
  type        = string
  default     = ""
}

variable "enricher_version" {
  description = "GitHub release version to download (e.g. '1.2.0'). Use 'latest' for the newest release. Ignored when enricher_zip_path is set."
  type        = string
  default     = "latest"
}

variable "config_repo_url" {
  description = "HTTPS clone URL of the GitOps config repo, used by the EventBridge-triggered periodic re-sync (e.g. https://github.com/org/repo)"
  type        = string
}

variable "config_repo_branch" {
  description = "Git branch the enricher Lambda should process"
  type        = string
  default     = "main"
}

variable "github_webhook_secret" {
  description = "Secret for validating GitHub webhook payloads"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_token" {
  description = "GitHub personal access token for cloning private config repos"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Scheduler Lambda ---

variable "scheduler_zip_path" {
  description = "Local path to a pre-built scheduler ZIP. If empty, the release is downloaded from GitHub."
  type        = string
  default     = ""
}

variable "scheduler_version" {
  description = "GitHub release version to download (e.g. '1.2.0'). Use 'latest' for the newest release. Ignored when scheduler_zip_path is set."
  type        = string
  default     = "latest"
}

variable "cw_namespace" {
  description = "CloudWatch namespace the scheduler Lambda queries for node capacity (must match agent_metric_namespace in the infra stack)"
  type        = string
}

# --- Observability ---

variable "observability_log_retention_days" {
  description = "Retention (days) for CloudWatch log groups managed by this stack."
  type        = number
  default     = 14
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for the enricher Lambda."
  type        = bool
  default     = true
}
