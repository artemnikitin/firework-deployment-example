variable "gcp_project" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "GCP region for the images bucket"
}

variable "images_bucket_name" {
  type        = string
  description = "Globally unique name for the node images bucket. Holds every architecture under an <arch>/ key prefix; nodes read the prefix matching their own architecture. Used by Packer to upload images and by data-plane nodes to rsync images at boot."
}

variable "packer_service_account" {
  type        = string
  default     = ""
  description = "Optional service account email for the CI/Packer pipeline. When set, grants objectCreator on the images bucket."
}
