# Infra Terraform Stack

This stack provisions the runtime environment where Firework nodes run.

It creates:

- VPC with public/private subnets across two AZs
- NAT gateways for outbound traffic from private subnets
- ALB (HTTPS) forwarding to Kibana instances
- Node security groups and IAM role
- Launch template + Auto Scaling Group for Firework nodes

This stack depends on:

- AMI from `packer/README.md`
- Config bucket outputs from `terraform/control-plane`
- Existing images bucket managed outside this stack

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS credentials with permissions for VPC, EC2, ALB, IAM
- Control-plane stack already applied (`config_bucket_name`, `config_bucket_arn`)
- Existing S3 images bucket and ARN
- Firework node AMI ID (built by Packer)

## Deploy

```bash
cd terraform/infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with AMI and bucket values
terraform init
terraform plan
terraform apply
```

## Required Inputs

| Variable | Source |
|---|---|
| `node_ami_id` | AMI built in `packer/` |
| `s3_configs_bucket_id` | `terraform/control-plane` output `config_bucket_name` |
| `s3_configs_bucket_arn` | `terraform/control-plane` output `config_bucket_arn` |
| `s3_images_bucket_id` | Existing bucket managed outside this stack |
| `s3_images_bucket_arn` | Existing bucket managed outside this stack |
| `node_key_name` | Existing EC2 key pair in target region |

## Observability

This stack now provisions basic runtime observability:

- CloudWatch dashboard for node + ALB signals
- CloudWatch log groups for `firework-agent` and Firecracker VM logs
- ALB access logs in an S3 bucket
- CloudWatch metric filters for common `firework-agent` error patterns

Useful outputs:

```bash
terraform output -raw observability_dashboard_name
terraform output -raw node_agent_log_group_name
terraform output -raw node_firecracker_log_group_name
terraform output -raw alb_access_logs_bucket_name
```

Quick checks:

```bash
DASHBOARD=$(terraform output -raw observability_dashboard_name)
AGENT_LOG_GROUP=$(terraform output -raw node_agent_log_group_name)
FC_LOG_GROUP=$(terraform output -raw node_firecracker_log_group_name)
ALB_LOG_BUCKET=$(terraform output -raw alb_access_logs_bucket_name)

# Stream node-level logs
aws logs tail "$AGENT_LOG_GROUP" --since 30m --follow
aws logs tail "$FC_LOG_GROUP" --since 30m --follow

# Confirm ALB access logs are being delivered
aws s3 ls "s3://$ALB_LOG_BUCKET/alb/AWSLogs/" --recursive

# Dashboard exists
aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD" --query 'DashboardName' --output text
```

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
# Confirm agent config looks correct (node_names, s3_bucket, etc.)
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
aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,`kbn`)].{Name:TargetGroupName,Arn:TargetGroupArn}' --output table

# Check health of a specific target group
aws elbv2 describe-target-health --target-group-arn <arn>
```

### Fast debug deploy of agent binary (no AMI rebuild)

From `firework-deployment-example/`, deploy a local binary to an existing node via SCP tunneled over SSM:

```bash
AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials-personal \
./scripts/push-agent-to-node.sh \
  --instance-id <instance-id> \
  --agent-path ../firework/bin/firework-agent-linux-arm64 \
  --ssh-key ~/.ssh/<your-key>.pem \
  --region us-east-1
```

Notes:
- Script no longer uses S3. It always copies directly via `scp/ssh` through Session Manager.
- Requires SSH over SSM (`AWS-StartSSHSession`) and a valid node key pair.

## Multi-node routing limitation

The ALB uses a single target group containing all nodes. Traefik on each node
only has routes for services scheduled to that node. In a multi-node deployment
(`node_count > 1` with anti-affinity), the ALB may forward a request to a node
that doesn't host the target service, causing 404/502 responses.

**For single-node deployments this is not a problem** (the default).

The complete fix requires one ALB target group per node and listener rules that
map each tenant hostname to the node where that service is scheduled. This
means the enricher must call ALB APIs after each scheduling cycle to update
rules — a larger architectural change not implemented here. See the comment in
`alb.tf` for details.

## Destroy

```bash
terraform destroy
```
