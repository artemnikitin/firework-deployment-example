# Control Plane Terraform Stack (ECS)

This stack provisions Firework control plane on ECS/Fargate with **separated roles**:

- `events` service: GitHub webhook ingestion (`/v1/events/github`)
- `registry` service: node enroll/register/heartbeat APIs (mTLS)
- `controller` service: leader-elected scheduling/publish loop
- shared S3 bucket for control-plane state and rendered `nodes/*.yaml`

## Architecture

- `events` runs behind a public HTTPS ALB
- `registry` runs behind a TCP NLB (set `registry_internal = true` for private-only exposure)
- `controller` runs as internal ECS tasks with no load balancer
- optional `step-ca` runs as a dedicated ECS service with an NLB endpoint and EFS-backed state

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS permissions for VPC, ECS, ELB, IAM, S3, CloudWatch, Secrets Manager (plus ACM/Route53 when auto-creating the events certificate)
- Either:
  - existing ACM certificate ARN for events ALB listener (`events_acm_certificate_arn`), or
  - `events_domain_name` so this stack can auto-create/validate an ACM cert in Route53
- GHCR image for control plane (`controlplane_image`)
- Optional: pre-created Secrets Manager ARNs for webhook/TLS/PKI values.
  - If omitted, this stack auto-generates demo secrets when `auto_create_demo_secrets = true` (default).
  - Optional GHCR pull credentials (`controlplane_image_pull_secret_arn`)
  - Optional GitHub token for private config repos

## Minimal Input (quick start)

For a demo deployment, only these are required in `terraform.tfvars`:

- `controlplane_image`
- one of:
  - `events_acm_certificate_arn`, or
  - `events_domain_name` (plus optional `events_hosted_zone_name` override)

Everything else can use defaults and auto-generated secrets.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Important Outputs

- `events_webhook_url` - configure GitHub push webhook to this URL
- `events_domain_name` - custom DNS name for events endpoint (when configured)
- `generated_github_webhook_secret` - webhook secret value (use this in GitHub when auto-generated)
- `registry_url` - set in node `agent.yaml` (`registry_url`)
- `config_bucket_name` + `config_prefix` - set in data-plane stack for agent config polling
- `step_ca_url` - set in data-plane stack (`step_ca_url`) when using AWS IID node cert bootstrap
- `step_ca_provisioner_name` - pass to data-plane stack (`step_ca_provisioner`)
- `step_ca_root_ca_secret_arn` - pass to data-plane stack (`step_ca_root_ca_secret_arn`)

## Optional step-ca PKI service

Set `enable_step_ca = true` to deploy a `smallstep/step-ca` ECS service.

- `step-ca` state is persisted on EFS so CA data survives task restarts.
- The step-ca bootstrap password is read from `step_ca_password_secret_arn` (or auto-generated when omitted and `auto_create_demo_secrets = true`).
- The task bootstraps an AWS IID provisioner (`step_ca_aws_provisioner_name`), scoped to `step_ca_aws_account_ids` (or the current account by default).
- Use `step_ca_internal = true` for private-only endpoint exposure when your node network can route to the control-plane VPC.
- Keep `step_ca_desired_count = 1`; this setup is single-writer and does not support active-active replicas.
- When `enable_step_ca = true`, legacy registry enrollment secrets (`registry_enrollment_ca_secret_arn`, `registry_enrollment_ca_key_secret_arn`, `registry_bootstrap_token_secret_arn`) are optional.
- Registry service trust remains configured by `registry_client_ca_secret_arn`; switching registry mTLS trust to step-ca is a later migration step.

For node bootstrap in the data-plane stack:

- set `step_ca_url` to this stack's `step_ca_url`
- set `step_ca_root_ca_secret_arn` to a secret containing the step-ca root certificate PEM
- set `step_ca_provisioner` to `step_ca_provisioner_name`

## Configure GitHub Webhook

1. In the config repo, open **Settings** -> **Webhooks** -> **Add webhook**
2. Set **Payload URL** to `events_webhook_url`
3. Set **Content type** to `application/json`
4. Set webhook **Secret** to the same value used in `github_webhook_secret_secret_arn` (or use `generated_github_webhook_secret` output when auto-generated)
5. Select **Just the push event**

## Destroy

```bash
terraform destroy
```
