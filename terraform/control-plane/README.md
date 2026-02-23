# Control Plane Terraform Stack

This stack provisions the control-plane layer used by Firework — the components that decide
_what_ runs _where_ and write per-node configs to S3 for the agents to consume.

It creates:

- S3 bucket for enriched node configs
- Enricher Lambda — processes GitOps pushes, enriches service specs, writes to S3
- Scheduler Lambda — bin-packs services across active EC2 nodes with anti-affinity support
- API Gateway webhook endpoint (`POST /webhook`) — receives GitHub push events
- IAM roles and policies for both Lambdas
- CloudWatch log groups and observability dashboard

Deploy this stack before `terraform/infra`, because infra consumes its outputs.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS credentials with permissions to create Lambda, API Gateway, S3, IAM resources
- Optional `github_token` for private Git config repositories

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

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

## Observability

This stack provisions:

- Lambda log groups (`/aws/lambda/<function-name>`) for both Lambdas
- API Gateway access log group (`/aws/apigateway/<project>-webhook-access`)
- CloudWatch dashboard for enricher Lambda, scheduler Lambda, and webhook API metrics
- Log-derived custom metrics in namespaces `Firework/<project_name>/Enricher` and `Firework/<project_name>/Scheduler`

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
