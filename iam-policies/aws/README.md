# AWS IAM policies

Replace `IMAGES_BUCKET_NAME` and `ACCOUNT_ID` in the JSON examples before use.

| File | Principal | Purpose |
|---|---|---|
| `01-ci-images-s3.json` | GitHub Actions CI | Upload rootfs images for every architecture to S3 |
| `02-terraform-deploy.json` | Terraform operator | Deploy AWS control and data planes, including starting/cancelling node instance refreshes |
| `03-packer-build.json` | Packer operator | Build the x86_64 AMI by default, or an explicitly configured ARM64 AMI |

Use short-lived role credentials for normal operation. The files are demo
policies and must remain below AWS's 6,144-character managed-policy limit
(whitespace is excluded). The image uploader's `s3:GetObject` permission also
authorizes the `HeadObject` API; there is no `s3:HeadObject` IAM action. See
[AWS's API-to-permission mapping](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-with-s3-policy-actions.html).
