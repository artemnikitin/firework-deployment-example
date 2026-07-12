variable "gcp_project" {
  type        = string
  description = "GCP project ID that owns the public Events edge."
}

variable "gcp_region" {
  type        = string
  description = "Default provider region; the Events address and certificate are global."
  default     = "us-central1"
}

variable "dns_zone_name" {
  type        = string
  description = "Pre-existing authoritative Cloud DNS managed zone that contains events_domain."
  default     = "firework-gcp"
}

variable "events_domain" {
  type        = string
  description = "Public Events hostname protected by the durable Certificate Manager certificate."

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", trimsuffix(var.events_domain, ".")))
    error_message = "events_domain must be a lowercase multi-label DNS hostname without a scheme, port, path, wildcard, or trailing dot."
  }
}

variable "edge_name" {
  type        = string
  description = "Stable resource-name prefix for the durable Events edge. Do not derive this from a disposable control-plane deployment name."
  default     = "firework-events-edge"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.edge_name))
    error_message = "edge_name must be a lowercase Compute Engine-compatible resource name."
  }
}
