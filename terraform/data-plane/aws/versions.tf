terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      # 6.33+ is required for cpu_options.nested_virtualization on
      # aws_launch_template.
      source  = "hashicorp/aws"
      version = "~> 6.33"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Component = "data-plane"
    }
  }
}
