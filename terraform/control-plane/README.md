# Control Plane Terraform Stack

This stack provisions the control-plane layer used by Firework — the components that decide
_what_ runs _where_ and write per-node configs to S3 for the agents to consume.

It creates:

- S3 bucket for enriched node configs
- Enricher Lambda (ARM64) — processes GitOps pushes, enriches service specs, writes to S3
- Scheduler Lambda (ARM64) — bin-packs services across active EC2 nodes with anti-affinity support
- API Gateway webhook endpoint (`POST /webhook`) — receives GitHub push events
- IAM roles and policies for both Lambdas
- CloudWatch log groups and observability dashboard

Deploy this stack before `terraform/infra`, because infra consumes its outputs.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS credentials with permissions to create Lambda, API Gateway, S3, IAM resources
- Optional `github_token` for private Git config repositories

If your environment requires a non-default credentials file:

```bash
export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials-personal
```

## Deploy

```bash
cd terraform/control-plane
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `project_name` | `firework-example` | Prefix for created resources |
| `aws_region` | `us-east-1` | AWS region |
| `config_repo_branch` | `main` | Git branch the enricher processes |
| `github_token` | `""` | GitHub token for cloning private repos (`contents:read`) |
| `github_webhook_secret` | `""` | Secret for GitHub webhook signature validation |
| `cw_namespace` | _(required)_ | CloudWatch namespace the scheduler queries for node capacity — must match `agent_metric_namespace` in the infra stack |
| `enricher_version` | `latest` | GitHub release version to download (ignored when `enricher_zip_path` is set) |
| `enricher_zip_path` | `""` | Local path to pre-built enricher ZIP |
| `scheduler_version` | `latest` | GitHub release version to download (ignored when `scheduler_zip_path` is set) |
| `scheduler_zip_path` | `""` | Local path to pre-built scheduler ZIP |
| `observability_log_retention_days` | `14` | Retention in days for Lambda/API Gateway log groups |
| `enable_xray_tracing` | `true` | Enable X-Ray tracing for both Lambdas |

## Using A Local Build

Both Lambdas support deploying a locally built ZIP instead of downloading a GitHub release.

```bash
# In the firework repo
make package-enricher   # produces bin/enricher.zip
make package-scheduler  # produces bin/scheduler.zip

# Deploy with local ZIPs
terraform apply \
  -var 'enricher_zip_path=../../firework/bin/enricher.zip' \
  -var 'scheduler_zip_path=../../firework/bin/scheduler.zip'
```

You can override just one and let the other download from GitHub:

```bash
terraform apply -var 'enricher_zip_path=../../firework/bin/enricher.zip'
```

## Outputs

| Output | Description |
|---|---|
| `config_bucket_name` | S3 bucket name for enriched node configs |
| `config_bucket_arn` | S3 bucket ARN for enriched node configs |
| `enricher_function_name` | Enricher Lambda function name |
| `webhook_url` | GitHub webhook URL (`POST`) |
| `enricher_log_group_name` | CloudWatch log group for enricher Lambda |
| `webhook_access_log_group_name` | CloudWatch log group for API Gateway webhook access logs |
| `scheduler_function_name` | Scheduler Lambda function name |
| `scheduler_function_arn` | Scheduler Lambda ARN (wired into enricher automatically) |
| `scheduler_log_group_name` | CloudWatch log group for scheduler Lambda |
| `observability_dashboard_name` | CloudWatch dashboard for control-plane signals |

## Observability

This stack provisions:

- Lambda log groups (`/aws/lambda/<function-name>`) for both Lambdas
- API Gateway access log group (`/aws/apigateway/<project>-webhook-access`)
- CloudWatch dashboard for enricher Lambda, scheduler Lambda, and webhook API metrics
- Log-derived custom metrics in namespace `Firework/<project_name>/Enricher`

Quick checks:

```bash
ENRICHER_LOG=$(terraform output -raw enricher_log_group_name)
SCHEDULER_LOG=$(terraform output -raw scheduler_log_group_name)
WEBHOOK_LOG=$(terraform output -raw webhook_access_log_group_name)
DASHBOARD=$(terraform output -raw observability_dashboard_name)

# Stream Lambda logs
aws logs tail "$ENRICHER_LOG" --since 30m --follow
aws logs tail "$SCHEDULER_LOG" --since 30m --follow

# Stream API Gateway webhook access logs
aws logs tail "$WEBHOOK_LOG" --since 30m --follow

# Dashboard exists
aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD" --query 'DashboardName' --output text
```

## Validate Lambda Before Webhook Setup

```bash
FUNCTION=$(terraform output -raw enricher_function_name)
BUCKET=$(terraform output -raw config_bucket_name)

aws lambda invoke \
  --function-name "$FUNCTION" \
  --cli-binary-format raw-in-base64-out \
  --log-type Tail \
  --payload '{
    "repository": {"clone_url": "https://github.com/YOUR_ORG/YOUR_CONFIG_REPO.git"},
    "ref": "refs/heads/main"
  }' \
  /tmp/enricher-response.json \
  --query 'LogResult' --output text | base64 -d

cat /tmp/enricher-response.json
```

Expected result:

- Lambda logs include `enrichment complete`
- Response body is `null`
- S3 contains `nodes/*.yaml`

```bash
aws s3 ls "s3://$BUCKET/" --recursive
```

## Configure GitHub Webhook

1. In the config repo, open **Settings** -> **Webhooks** -> **Add webhook**
2. Set **Payload URL** to `webhook_url` output
3. Set **Content type** to `application/json`
4. If using `github_webhook_secret`, set the same value in webhook **Secret**
5. Select **Just the push event**

## Destroy

```bash
terraform destroy
```
