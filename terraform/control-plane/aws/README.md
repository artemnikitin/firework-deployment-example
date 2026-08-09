# Control Plane Terraform Stack (ECS)

This stack provisions Firework control plane on ECS/Fargate. The demo default
uses one ECS service for every role; a split layout remains available when
independent scaling or isolation is more important than simplicity:

- `all` service (default): GitHub webhook ingestion, node registry, controller,
  and authenticated read-only API/UI in one task
- `split` mode: separate `events`, `registry`, `controller`, and `api` services
- shared S3 bucket for control-plane state and rendered `nodes/*.yaml`

## Architecture

- `events` and `api` share one public HTTPS ALB but use separate origins.
  `events.<domain>/v1/events/github` routes to events and unmatched events-host
  requests return 404; `status.<domain>` routes to the API/UI.
- `registry` runs behind a public TCP NLB; the control-plane and data-plane
  currently use separate VPCs, so no private-only option is exposed here
- `split` mode gives `api` a separate task role restricted to S3 list/get
  permissions; the combined service deliberately uses the shared control-plane
  role because all roles share one task
- Node enrollment uses a bootstrap token plus an enrollment CA. The token is a
  shared Secrets Manager credential, and the default empty
  `registry_bootstrap_node_id` allows any node ID to use it. AWS IID-based
  enrollment is a known gap in this demo.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS permissions for VPC, ECS, ELB, IAM, S3, CloudWatch, Secrets Manager (plus ACM/Route53 when auto-creating the events and status certificates)
- `events_domain_name` for webhook hostname routing and DNS.
- Optional existing ACM certificate ARN for the events hostname
  (`events_acm_certificate_arn`); otherwise the stack creates and validates it.
- `status_domain_name` defaults to `status.<events-domain suffix>`; optionally
  override it and/or supply `status_acm_certificate_arn`.
- GHCR image for control plane (`controlplane_image`)
- Optional: pre-created Secrets Manager ARNs for webhook/TLS/bootstrap-token
  enrollment values.
  - If omitted, this stack auto-generates demo secrets when `auto_create_demo_secrets = true` (default).
  - Optional GHCR pull credentials (`controlplane_image_pull_secret_arn`)
  - Optional GitHub token for private config repos
- Optional startup reconciliation:
  - `reconcile_on_start = true`
  - `git_repo_url = "https://github.com/<owner>/<repo>"`

## Minimal Input (quick start)

For a demo deployment, only these are required in `terraform.tfvars`:

- `controlplane_image`
- `events_domain_name` (plus optional `events_hosted_zone_name` override)

Everything else can use defaults and auto-generated secrets.

When `controlplane_image` uses a mutable tag such as `dev`, set
`controlplane_deployment_revision` to the published image digest after every
push. Changing the revision forces all control-plane ECS services to start new
Fargate tasks, which pull the current image. Set
`controlplane_service_mode = "split"` to retain one ECS service per role.
The `controlplane_*` CPU, memory, and desired-count inputs apply to the default
combined service; role-specific CPU, memory, and desired-count inputs apply in
split mode, including multiple instances of each role service.

If you enable `reconcile_on_start`, you must also set `git_repo_url`.

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
- `api_url` - open the UI or configure `fireworkctl`
- `status_domain_name` - dedicated UI/API hostname
- `operator_token_secret_arn` - retrieve the operator token explicitly from
  Secrets Manager; the token value is never a Terraform output
- `events_domain_name` - custom DNS name for events endpoint (when configured)
- `generated_github_webhook_secret` - webhook secret value (use this in GitHub when auto-generated)
- `registry_url` - set in node `agent.yaml` (`registry_url`)
- `config_bucket_name` + `config_prefix` - consumed automatically by the data-plane stack
- `registry_server_name`, `registry_client_ca_secret_arn`, and
  `registry_bootstrap_token_secret_arn` - consumed automatically by the data-plane stack

## Configure GitHub Webhook

1. In the config repo, open **Settings** -> **Webhooks** -> **Add webhook**
2. Set **Payload URL** to `events_webhook_url`
3. Set **Content type** to `application/json`
4. Set webhook **Secret** to the same value used in `github_webhook_secret_secret_arn` (or use `generated_github_webhook_secret` output when auto-generated)
5. Select **Just the push event**

## Access deployment status

The dedicated status HTTPS origin serves the UI and API; the events hostname
serves only the exact webhook path. Retrieve the operator token into a
mode-0600 file and keep it out of command arguments:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw operator_token_secret_arn)" \
  --query SecretString --output text > operator-token

chmod 0600 operator-token

fireworkctl --endpoint "$(terraform output -raw api_url)" \
  --token-file operator-token nodes
```

Rotate access by adding a new secret version and forcing a new control-plane
deployment. In `split` mode the API task cannot write or delete control-plane
state; the default combined task uses the shared control-plane role for all
roles, including the controller's write access.

## Destroy

```bash
terraform destroy
```
