# Firework Packer AMI Build

This document covers building the Firework node AMI in `packer/aws/`.

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

## Quick Start

```bash
cp firework-node-aws.auto.pkrvars.hcl.example firework-node-aws.auto.pkrvars.hcl
# edit firework-node-aws.auto.pkrvars.hcl
packer init .
packer build -var-file="firework-node-aws.auto.pkrvars.hcl" .
```

The AMI ID is printed at the end of the build output.

## Agent Binary Download Behavior

When `firework_agent_path` is empty, `../scripts/03-install-agent.sh` downloads `firework-agent-linux-arm64` from GitHub Releases:

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
