# IAM Policies

Minimal IAM policies for each component. Replace the placeholder values before use:

| Placeholder | Replace with |
|---|---|
| `IMAGES_BUCKET_NAME` | S3 images bucket name (from `terraform/infra` output: `images_bucket_name`) |
| `CONFIGS_BUCKET_NAME` | S3 configs bucket name (from `terraform/control-plane` output: `config_bucket_name`) |
| `ACCOUNT_ID` | Your AWS account ID |

## Policies

| # | File                       | Used by | Notes |
|---|----------------------------|---|---|
| 1 | `01-ci-images-s3.json`     | GitHub Actions CI (`firework-gitops-example`) | Read/write rootfs images to S3. Create an IAM user, attach this policy, and set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as repo secrets. |
| 2 | `02-terraform-deploy.json` | Terraform operator | Full deploy permissions: VPC, EC2, Auto Scaling, ALB, ACM, Route53, S3, Lambda, API Gateway, IAM, SSM, CloudWatch. Includes CloudWatch Log Delivery APIs needed for API Gateway access logs (`logs:CreateLogDelivery`, etc.) and S3 permissions for ALB access-log buckets (`*-alb-logs-*`). **Replace `ACCOUNT_ID`, `IMAGES_BUCKET_NAME`, and `CONFIGS_BUCKET_NAME` before applying.** |
| 3 | `03-packer-build.json`     | Packer operator | Build AMIs (launch instances, create snapshots/images, manage temp security groups). |

## Usage

### Create an IAM user with a specific policy

```bash
# Example: create the CI user for image uploads
aws iam create-user --user-name firework-ci-images

aws iam create-policy \
  --policy-name firework-ci-images-s3 \
  --policy-document file://01-ci-images-s3.json

aws iam attach-user-policy \
  --user-name firework-ci-images \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/firework-ci-images-s3

aws iam create-access-key --user-name firework-ci-images
```

### Terraform and Packer (policies 2 and 3)

These can be attached to either:
- An **IAM user** for local development (`aws iam create-access-key`)
- An **IAM role** assumed via SSO/federation for team use

For a quick demo, a single IAM user with policy 4 attached works. For production, use separate roles with session-based credentials.
