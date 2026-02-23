packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type        = string
  default     = "t4g.large"
  description = "Instance type for the Packer builder. Any ARM64 instance works — the build only installs binaries and does not run Firecracker. Metal instances are only required at runtime (infra stack). Avoid metal here: they take 15-20 min to launch/terminate."
}

variable "source_ami_name" {
  type        = string
  default     = "al2023-ami-2023.*-kernel-6.1-arm64"
  description = "Name filter for the base AMI (Amazon Linux 2023, ARM64)"
}

variable "source_ami_owner" {
  type        = string
  default     = "amazon"
  description = "Owner of the base AMI"
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
  description = "Local path to a pre-built firework-agent binary (linux/arm64). Required when no GitHub release exists. Build with: make build-linux-arm64"
}

variable "firework_agent_version" {
  type        = string
  default     = "latest"
  description = "GitHub release version to download (latest, 1.2.3, or v1.2.3). Ignored if firework_agent_path is set."
}

variable "github_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "GitHub token for downloading release assets from private repos (optional for public repos)."
}

variable "ssh_username" {
  type    = string
  default = "ec2-user"
}

variable "ami_name_prefix" {
  type    = string
  default = "firework-node"
}

variable "volume_size" {
  type    = number
  default = 50
}

variable "aws_poll_delay_seconds" {
  type        = number
  default     = 15
  description = "Delay between AWS waiter polling attempts."
}

variable "aws_poll_max_attempts" {
  type        = number
  default     = 120
  description = "Max AWS waiter polling attempts (120 * 15s = 30m). Increase if using a metal builder instance, which can take significantly longer to terminate."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID to launch the builder instance in. Required when there is no default VPC."
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Subnet ID to launch the builder instance in. Must be a public subnet when vpc_id is set."
}

# -----------------------------------------------------------------------------
# Source: Amazon EBS (ARM64 / Graviton)
# -----------------------------------------------------------------------------

source "amazon-ebs" "firework_node" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  # AWS resources can take time to reach terminal states (notably instance
  # termination), so increase waiter budget beyond the default ~10 minutes.
  aws_polling {
    delay_seconds = var.aws_poll_delay_seconds
    max_attempts  = var.aws_poll_max_attempts
  }

  source_ami_filter {
    filters = {
      name                = var.source_ami_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "arm64"
    }
    most_recent = true
    owners      = [var.source_ami_owner]
  }

  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "Firework node AMI (arm64) with Firecracker ${var.firecracker_version} and firework-agent"

  # Required when the account has no default VPC.
  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  # Assign a public IP so Packer can SSH into the builder instance.
  # Required when launching in a public subnet of a non-default VPC.
  associate_public_ip_address = var.subnet_id != "" ? true : null

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  run_tags = {
    Name     = "${var.ami_name_prefix}-builder"
    Built_By = "packer"
  }

  tags = {
    Name                = "${var.ami_name_prefix}-{{timestamp}}"
    Base_AMI            = "{{ .SourceAMI }}"
    Architecture        = "arm64"
    Firecracker_Version = var.firecracker_version
    Built_By            = "packer"
  }
}

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

build {
  sources = ["source.amazon-ebs.firework_node"]

  # --- System setup and KVM configuration ---
  provisioner "shell" {
    script = "scripts/01-system-setup.sh"
  }

  # --- Install Firecracker ---
  provisioner "shell" {
    script = "scripts/02-install-firecracker.sh"
    environment_vars = [
      "FIRECRACKER_VERSION=${var.firecracker_version}",
    ]
  }

  # --- Download Firecracker-compatible kernel ---
  provisioner "shell" {
    script = "scripts/02a-download-kernel.sh"
    environment_vars = [
      "FIRECRACKER_VERSION=${var.firecracker_version}",
    ]
  }

  # --- Install firework-agent (upload pre-built binary if provided) ---
  provisioner "file" {
    source      = var.firework_agent_path != "" ? var.firework_agent_path : "/dev/null"
    destination = "/tmp/firework-agent"
    only        = var.firework_agent_path != "" ? ["amazon-ebs.firework_node"] : []
  }

  provisioner "shell" {
    script = "scripts/03-install-agent.sh"
    environment_vars = [
      "AGENT_PATH=${var.firework_agent_path}",
      "AGENT_VERSION=${var.firework_agent_version}",
      "AGENT_GITHUB_TOKEN=${var.github_token}",
    ]
  }

  # --- Create systemd service and directories ---
  provisioner "shell" {
    script = "scripts/04-configure-service.sh"
  }

  # --- Install Traefik ---
  provisioner "shell" {
    script = "scripts/05-install-traefik.sh"
    environment_vars = [
      "TRAEFIK_VERSION=${var.traefik_version}",
    ]
  }

  # --- Configure Traefik systemd service ---
  provisioner "shell" {
    script = "scripts/06-configure-traefik.sh"
  }

  # --- Cleanup ---
  provisioner "shell" {
    script = "scripts/99-cleanup.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
