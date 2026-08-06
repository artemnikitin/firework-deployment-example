# Firework Packer AMI Build

This document covers building the Firework node AMI in `packer/aws/`.

## Architecture

The template builds an **x86_64** AMI by default, matching the default
`node_instance_type` in the data-plane stack (a virtual instance using nested
virtualization rather than bare metal). Set `architecture = "arm64"` together
with an arm64 `instance_type` and `source_ami_name` to build for bare-metal
Graviton nodes instead.

The architecture must be consistent across three places:

| Setting | Location |
| --- | --- |
| `architecture` | `packer/aws/*.pkrvars.hcl` |
| `node_ami_architecture` and `node_instance_type` | data-plane stack |
| rootfs image set | S3 images bucket (`firework-gitops-example` builds both) |

Host and guest architecture must match, so pointing an x86_64 node at an arm64
rootfs bucket fails at microVM start, not at deploy time.

All provisioning scripts in `packer/scripts/` resolve their downloads from
`uname -m`, so they need no changes between architectures.

The current pinned components are Firecracker `1.16.1`, Traefik `3.7.10`, and
the Firecracker CI kernel family `1.15`. Firecracker `1.16.1` is the latest
binary release, but the official CI bucket currently does not publish a
`v1.16` kernel prefix, so the kernel family is pinned independently.

## What this AMI contains

- Amazon Linux 2023 (x86_64 by default, arm64 supported)
- Firecracker + jailer
- Firecracker-compatible `vmlinux-5.10.x` kernel
- `firework-agent` binary
- `amazon-ssm-agent` enabled
- `e2fsprogs` and `amazon-efs-utils` for local ext4 pools and TLS EFS mounts
- systemd unit and required directories

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer/downloads) >= 1.9
- AWS credentials with permissions to create EC2 AMI build resources
- A VPC and public subnet if your account has no default VPC
- Optional: GitHub token if downloading release assets from a private repository

## Quick Start

```bash
cp firework-node-aws.auto.pkrvars.hcl.example firework-node-aws.auto.pkrvars.hcl
# edit firework-node-aws.auto.pkrvars.hcl
packer init .
packer build -var-file="firework-node-aws.auto.pkrvars.hcl" .
```

The AMI ID is printed at the end of the build output.

## Agent Binary Download Behavior

When `firework_agent_path` is empty, `../scripts/03-install-agent.sh` downloads the asset matching the builder architecture (`firework-agent-linux-amd64` or `firework-agent-linux-arm64`) from GitHub Releases:

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
packer build -on-error=abort firework-node-aws.pkr.hcl
```

This skips cleanup waiting and leaves resources for inspection.
