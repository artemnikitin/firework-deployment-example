# Infra Terraform Stack

This stack provisions the data plane with Firework.

It creates:

- VPC with public/private subnets across two AZs
- NAT gateways for outbound traffic from private subnets
- ALB (HTTPS) forwarding to Traefik on Firework nodes
- Node security groups and IAM role
- Launch template + Auto Scaling Group for Firework nodes

This stack depends on:

- AMI from [packer/aws/README.md](../../../packer/aws/README.md)
- Config bucket outputs from [terraform/control-plane/aws/README.md](../../control-plane/aws/README.md)
- Existing images bucket managed outside this stack

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS credentials with permissions for VPC, EC2, ALB, IAM
- Control-plane stack already applied
- By default, this stack auto-wires config/registry/step-ca values from `../../control-plane/aws/terraform.tfstate`
  (`use_control_plane_remote_state = true`, `control_plane_state_path = "../../control-plane/aws/terraform.tfstate"`)
  - If your control-plane state lives elsewhere, point `control_plane_state_path` to it or disable auto-wiring and set manual overrides.
  - For S3 config bucket values, auto-wired control-plane outputs are preferred over manual tfvars when present (to avoid stale overrides).
- Existing S3 images bucket and ARN
- Firework node AMI source (explicit ID, name pattern lookup, or Packer manifest)

Apply order is strict: deploy `terraform/control-plane/aws` first, then `terraform/data-plane/aws`.

## Minimal Input (quick start)

With control-plane auto-wiring enabled, the minimum required `terraform.tfvars` values are:

- `domain_name`
- `s3_images_bucket_id`
- `s3_images_bucket_arn`
- `node_key_name`

`node_ami_id` is optional when one of these AMI auto-resolution paths is available.

## Routing domain

`domain_name` is the single source of truth for the wildcard ACM certificate and
the agent's `ingress_domain`. The data plane passes `domain_name` into each
node's `/etc/firework/agent.yaml` as `ingress_domain`, so a service whose GitOps
metadata sets `subdomain: tenant-1` is served at `tenant-1.<domain_name>`. The
wildcard certificate covers a single label (`*.<domain_name>`), so
`metadata.subdomain` must be exactly one label.

## Node AMI resolution

Node AMI is resolved in this priority order:

1. `node_ami_id` (explicit override)
2. `node_ami_name_pattern` (latest matching AMI in AWS)
3. `packer_manifest_path` (latest AMI for `aws_region` from `packer/aws/manifest.json` when `use_packer_manifest_ami = true`)

Notes:

- For `node_ami_name_pattern`, you can pass a partial name (for example `firework-node`); Terraform automatically searches as `*firework-node*`.
- Pattern lookup uses owners from `node_ami_owners` (default `["self"]`) and architecture `node_ami_architecture` (default `arm64`).

## Node certificate bootstrap modes

Two certificate bootstrap modes are supported for registry mTLS:

- Preferred: `step-ca` AWS IID mode
  - Auto-wired from control-plane outputs when available (`step_ca_url`, `step_ca_root_ca_secret_arn`, `step_ca_provisioner_name`)
  - You can still override with explicit tfvars values
  - Node obtains cert/key using `step ca certificate --provisioner <aws-iid>`
  - Node runs `step ca renew --daemon` for automatic renewal
  - Node does **not** need `registry_bootstrap_token_secret_arn`
  - Ensure the registry service trusts the same CA root before enabling this mode
- Legacy: registry enrollment token mode
  - Auto-wired from control-plane outputs when available (`registry_client_ca_secret_arn`, `registry_bootstrap_token_secret_arn`)
  - You can still override with explicit tfvars values
  - Agent enrolls directly with the registry endpoint

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Observability

This stack now provisions basic runtime observability:

- CloudWatch dashboard for node + ALB signals
- CloudWatch log groups for `firework-agent` and Firecracker VM logs
- ALB access logs in an S3 bucket
- CloudWatch metric filters for common `firework-agent` error patterns
- CloudWatch metric filters for controller errors that read `/ecs/<project>/controlplane-controller` (created by the control-plane stack)

## Debugging

Nodes live in private subnets. All access goes through AWS Systems Manager Session Manager — no SSH, no bastion.

### Connect to a node

```bash
# Get the instance ID
terraform output -json node_instance_ids

# Open a shell
aws ssm start-session --target <instance-id>
```

### Check agent status

```bash
systemctl status firework-agent
```

### Follow agent logs

```bash
# Stream live
journalctl -u firework-agent -f

# Last 100 lines
journalctl -u firework-agent -n 100 --no-pager
```

Key things to look for in logs:
- `microVM started` — VM launched successfully
- `microVM exited cleanly` shortly after start — crash loop; check images and network config
- `linked service not found or has no network` — a service has `network: false` or is missing; check tenant YAML
- `reconciliation plan creates=N updates=N deletes=N` — agent picked up new config from S3

### Check agent config and images

```bash
# Confirm agent config looks correct (node_names, s3_bucket/s3_prefix, registry_url)
cat /etc/firework/agent.yaml

# Confirm all expected rootfs images are downloaded
ls -lh /var/lib/images/
```

### Query the agent API

The agent exposes a local HTTP API on port 8081:

```bash
# Overall status: running services, health, last revision
curl -s localhost:8081/status | jq .

# Health check results per service
curl -s localhost:8081/health | jq .

# Liveness probe
curl -s localhost:8081/healthz

# Prometheus-style runtime metrics (reconcile/image sync/config freshness)
curl -s localhost:8081/metrics
```

### Check running microVMs

```bash
# List active Firecracker processes
ps aux | grep firecracker

# List VM state directories
ls /var/lib/firework/vms/
```

### Check ALB target group health

Run this outside the node (from your workstation) to see what the ALB sees:

```bash
# List target groups
aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,`trafk`)].{Name:TargetGroupName,Arn:TargetGroupArn}' --output table

# Check health of a specific target group
aws elbv2 describe-target-health --target-group-arn <arn>
```

### Fast debug deploy of agent binary (no AMI rebuild)

From `firework-deployment-example/`, deploy a local binary to an existing node via SCP tunneled over SSM:

```bash
./scripts/push-agent-to-node.sh \
  --instance-id <instance-id> \
  --agent-path ../firework/bin/firework-agent-linux-arm64 \
  --ssh-key ~/.ssh/<your-key>.pem \
  --region us-east-1
```

Notes:
- Requires SSH over SSM (`AWS-StartSSHSession`) and a valid node key pair.

## Multi-node routing

The ALB uses a single target group containing all nodes. Traefik on each node
handles routing for both its own locally-scheduled services and services scheduled
on peer nodes.

For remote services, the agent reads all rendered node configs from S3, and for
each peer service that has a `metadata.host` and at least one `port_forwards` entry,
it writes a `remote-{service}.yaml` Traefik dynamic config file that proxies requests
to the peer node's host IP and forwarded port. Traefik watches the directory and picks
up the change without a reload.

This means a request that the ALB round-robins to any node will be correctly proxied
to the node where the target service is actually scheduled.

Remaining constraints:
- Remote routing requires `host_ip` to be populated in the peer node's rendered config
  (set automatically from the registry when nodes send heartbeats).
- The remote service must have at least one `port_forwards` entry so the host-side port
  is known.

## Destroy

```bash
terraform destroy
```
