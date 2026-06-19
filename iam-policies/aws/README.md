# AWS IAM policies

Replace `IMAGES_BUCKET_NAME` and `ACCOUNT_ID` in the JSON examples before use.

| File | Principal | Purpose |
|---|---|---|
| `01-ci-images-s3.json` | GitHub Actions CI | Upload ARM64 rootfs images to S3 |
| `02-terraform-deploy.json` | Terraform operator | Deploy AWS control and data planes |
| `03-packer-build.json` | Packer operator | Build the ARM64 AMI |

Use short-lived role credentials for normal operation. The files are demo
policies and must remain below AWS's 6,144-character managed-policy limit.
