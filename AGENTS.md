# AGENTS.md

## Project

This is an example AWS and GCP deployment for Firework using Packer and Terraform. It is demo-oriented, not production-hardened.

## Layout

- `packer/`: x86_64 Firework node images for AWS and GCP, with ARM64 also supported on AWS; includes Firecracker, kernel, agent, Traefik, and provider access tooling.
- `terraform/control-plane/`: ECS/Fargate or GKE control plane, one all-role service by default (with an optional split layout), state/config bucket, and provider-specific edge wiring.
- `terraform/data-plane/`: provider VPC/network, load balancers, node groups, and node IAM/security groups.
- `iam-policies/`: example IAM policies for CI/deploy users.
- `scripts/push-agent-to-node.sh`: debug deploy of a local agent binary via SSM SSH tunnel.

## Conventions

- Keep `control-plane` and `data-plane` Terraform stacks independently valid.
- Preserve deploy order: Packer AMI, control plane, then data plane.
- Prefer examples and defaults that are explicit about demo-only assumptions.
- Do not introduce secrets into tracked files; keep `*.tfvars` and Packer var files local.
- When doing changes make sure that all the needed permissions are updated in `iam-policies/`.
- Make sure to keep the permissions in `iam-policies/` files below 6144 characters per policy (this is AWS limit).

## Shared contracts

- When changing configuration, identity, ports, or control-plane outputs, trace
  the affected Terraform stacks, startup templates, IAM/firewalls, and core
  Firework consumers. Keep both providers aligned where they share the contract.
- For architecture changes, check the Packer image, instance type, kernel,
  Firecracker/agent binaries, and GitOps rootfs/guest-init architecture together.
  Required images must be published under the matching architecture prefix before
  nodes use them. Report companion changes and rollout ordering; unrelated changes
  do not require a cross-repository audit.

## Validation

Select checks for the changed files. Paths below are relative to the repository
root; run each command from the working directory listed.

| Change | Working directory | Checks |
| --- | --- | --- |
| Documentation only | Repository root | Check formatting and links; verify changed commands, paths, defaults, and behavioral claims against source. No Terraform/Packer execution required. |
| Terraform | Each affected `terraform/control-plane/{aws,gcp}`, `terraform/data-plane/{aws,gcp}`, or `terraform/dns-foundation` directory | `terraform fmt -check -recursive .`, `terraform init -backend=false`, `terraform validate`, then `tflint --init && tflint` |
| AWS Packer | `packer/aws` | `packer fmt -check .`, `packer init .`, then `packer validate .` |
| GCP Packer | `packer/gcp` | `packer fmt -check .`, `packer init .`, then `packer validate -var=gcp_project=test-project .` |
| Packer shell scripts | Repository root | `shellcheck packer/aws/*.sh packer/gcp/*.sh packer/scripts/*.sh` |
| Node startup templates | Repository root | `shellcheck terraform/data-plane/aws/templates/user-data.sh.tpl terraform/data-plane/gcp/templates/startup-script.sh.tpl` |

For shared scripts or wiring changes, include every affected provider/stack.
Terraform validation and linting do not establish that real remote-state outputs,
permissions, bootstrap, or deployment behavior work. For wiring changes, inspect
both the exported outputs and their consumers, including absent and populated
state paths. Report checks performed and any remaining deployment verification.

For CI-equivalent local validation run the logic/steps from `.github/workflows/ci.yaml`.

Only run `terraform plan/apply/destroy`, `packer build`, AWS/GCP CLI mutations, or `scripts/push-agent-to-node.sh` when explicitly requested. Cloud validation can be batched across changes; it is not required for every edit.
