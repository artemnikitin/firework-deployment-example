# Firework Packer AMI Build

This document covers building the Firework node AMI in `packer/`.

## What this AMI contains

- Amazon Linux 2023 (ARM64)
- Firecracker + jailer
- Firecracker-compatible `vmlinux-5.10.x` kernel
- `firework-agent` binary
- `amazon-ssm-agent` enabled
- systemd unit and required directories

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer/downloads) >= 1.9
- AWS credentials with permissions to create EC2 AMI build resources
- A VPC and public subnet if your account has no default VPC
- Optional: GitHub token if downloading release assets from a private repository

If your environment uses a non-default credentials file, export it before running:

```bash
export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials-personal
```

## Quick Start

```bash
cd packer
cp firework-node.auto.pkrvars.hcl.example firework-node.auto.pkrvars.hcl
packer init firework-node.pkr.hcl
packer build \
  -var-file="firework-node.auto.pkrvars.hcl" \
  firework-node.pkr.hcl
```

The AMI ID is printed at the end of the build output.

## Key Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region for build resources |
| `instance_type` | `c6g.metal` | Build instance type (must support KVM for validation) |
| `firecracker_version` | `1.12.0` | Firecracker release version to install |
| `firework_agent_path` | `""` | Local path to pre-built `firework-agent` (skips GitHub download) |
| `firework_agent_version` | `latest` | Release version to download (`latest`, `1.2.3`, or `v1.2.3`) |
| `github_token` | `""` | Token for private GitHub release downloads (optional for public repos) |
| `source_ami_name` | `al2023-ami-2023.*-kernel-6.1-arm64` | Base AMI name filter |
| `source_ami_owner` | `amazon` | Base AMI owner |
| `volume_size` | `50` | Root volume size in GB |
| `aws_poll_delay_seconds` | `30` | Delay between AWS waiter polling attempts |
| `aws_poll_max_attempts` | `60` | Max waiter attempts (`60 * 30s = 30m`) |
| `vpc_id` | `""` | VPC ID (required if no default VPC) |
| `subnet_id` | `""` | Public subnet ID for builder instance |
| `ami_name_prefix` | `firework-node` | Name prefix for created AMIs |
| `ssh_username` | `ec2-user` | SSH username for builder host |

## Agent Binary Download Behavior

When `firework_agent_path` is empty, `scripts/03-install-agent.sh` downloads `firework-agent-linux-arm64` from GitHub Releases:

- `firework_agent_version = "latest"` uses the latest release
- `firework_agent_version = "1.2.3"` and `"v1.2.3"` both resolve to tag `v1.2.3`
- if `github_token` is set, release metadata and asset download go through GitHub API (works for private and public repos)
- if `github_token` is empty, public release URLs are used

After installation, the script verifies the binary by running:

- `firework-agent --version`
- `firework-agent --help` (must emit output)

## Debugging And Failure Handling

- If cleanup is slow, increase `aws_poll_max_attempts`.
- For faster fail/debug cycles, run Packer with:

```bash
packer build -on-error=abort firework-node.pkr.hcl
```

This skips cleanup waiting and leaves resources for inspection.

## Example Commands

Public repository, latest release:

```bash
packer build -var "firework_agent_version=latest" firework-node.pkr.hcl
```

Private repository, latest release:

```bash
packer build \
  -var "firework_agent_version=latest" \
  -var "github_token=<token>" \
  firework-node.pkr.hcl
```

Specific release tag:

```bash
packer build -var "firework_agent_version=v0.3.0" firework-node.pkr.hcl
```

Local pre-built agent binary:

```bash
packer build -var "firework_agent_path=../firework/bin/firework-agent" firework-node.pkr.hcl
```

## Directory Structure

```
packer/
  firework-node.pkr.hcl
  firework-node.auto.pkrvars.hcl.example
  scripts/
    01-system-setup.sh
    02-install-firecracker.sh
    02a-download-kernel.sh
    03-install-agent.sh
    04-configure-service.sh
    99-cleanup.sh
```
