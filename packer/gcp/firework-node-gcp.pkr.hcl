packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "gcp_project" {
  type = string
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "n2-standard-2"
}

variable "firecracker_version" {
  type    = string
  default = "1.12.0"
}

variable "traefik_version" {
  type    = string
  default = "3.3.4"
}

variable "firework_agent_path" {
  type        = string
  default     = ""
  description = "Optional local linux/amd64 firework-agent binary"
}

variable "firework_agent_version" {
  type    = string
  default = "latest"
}

variable "github_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "image_name_prefix" {
  type    = string
  default = "firework-node"
}

variable "volume_size" {
  type    = number
  default = 50
}

source "googlecompute" "firework_node" {
  project_id              = var.gcp_project
  zone                    = var.zone
  machine_type            = var.machine_type
  source_image_family     = "debian-12"
  source_image_project_id = ["debian-cloud"]

  image_name        = "${var.image_name_prefix}-{{timestamp}}"
  image_family      = "firework-node-gcp"
  image_description = "Firework node (x86_64) with Firecracker ${var.firecracker_version}"
  image_labels = {
    architecture        = "x86-64"
    firecracker_version = replace(var.firecracker_version, ".", "-")
    built_by            = "packer"
  }

  disk_size    = var.volume_size
  disk_type    = "pd-ssd"
  ssh_username = "packer"
  use_os_login = true
}

build {
  sources = ["source.googlecompute.firework_node"]

  provisioner "shell" {
    script = "${path.root}/01-system-setup-gcp.sh"
  }

  provisioner "shell" {
    script           = "${path.root}/../scripts/02-install-firecracker.sh"
    environment_vars = ["FIRECRACKER_VERSION=${var.firecracker_version}"]
  }

  provisioner "shell" {
    script           = "${path.root}/../scripts/02a-download-kernel.sh"
    environment_vars = ["FIRECRACKER_VERSION=${var.firecracker_version}"]
  }

  provisioner "file" {
    source      = var.firework_agent_path != "" ? var.firework_agent_path : "/dev/null"
    destination = "/tmp/firework-agent"
    only        = var.firework_agent_path != "" ? ["googlecompute.firework_node"] : []
  }

  provisioner "shell" {
    script = "${path.root}/../scripts/03-install-agent.sh"
    environment_vars = [
      "AGENT_PATH=${var.firework_agent_path}",
      "AGENT_VERSION=${var.firework_agent_version}",
      "AGENT_GITHUB_TOKEN=${var.github_token}",
    ]
  }

  provisioner "shell" {
    script = "${path.root}/../scripts/04-configure-service.sh"
  }

  provisioner "shell" {
    script           = "${path.root}/../scripts/05-install-traefik.sh"
    environment_vars = ["TRAEFIK_VERSION=${var.traefik_version}"]
  }

  provisioner "shell" {
    script = "${path.root}/../scripts/06-configure-traefik.sh"
  }

  provisioner "shell" {
    script = "${path.root}/../scripts/99-cleanup.sh"
  }
}
