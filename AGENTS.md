# AGENTS.md

## Project

This is an example AWS deployment for Firework using Packer and Terraform. It is demo-oriented, not production-hardened.

## Layout

- `packer/`: ARM64 Firework node AMI with Firecracker, kernel, agent, Traefik, and SSM.
- `terraform/control-plane/`: ECS/Fargate control-plane services, S3 state/config bucket, optional step-ca.
- `terraform/data-plane/`: VPC, ALB, Auto Scaling Group, node IAM/security groups.
- `iam-policies/`: example IAM policies for CI/deploy users.
- `scripts/push-agent-to-node.sh`: debug deploy of a local agent binary via SSM SSH tunnel.

## Conventions

- Keep `control-plane` and `data-plane` Terraform stacks independently valid.
- Preserve deploy order: Packer AMI, control plane, then data plane.
- Prefer examples and defaults that are explicit about demo-only assumptions.
- Do not introduce secrets into tracked files; keep `*.tfvars` and Packer var files local.
- When doing changes make sure that all the needed permissions are updated in `iam-policies/`.
- Make sure to keep the permissions in `iam-policies/` files below 6144 characters per policy (this is AWS limit).

## Validation

Run from the relevant stack directory:

- `terraform fmt -check -recursive .`
- `terraform init -backend=false`
- `terraform validate`
- `tflint --init && tflint`
- `packer fmt -check .`
- `packer init . && packer validate .`
- `shellcheck packer/scripts/*.sh terraform/data-plane/templates/user-data.sh.tpl`

For CI-equivalent local validation run the logic/steps from `.github/workflows/ci.yaml`.

Only run `terraform plan/apply/destroy`, `packer build`, AWS CLI mutations, or `scripts/push-agent-to-node.sh` when explicitly requested.
