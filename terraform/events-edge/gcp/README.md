# GCP Events edge foundation

This is the durable public edge for the Events webhook endpoint. It owns the
global static IP, public A record, Certificate Manager DNS authorization,
Google-managed certificate, and certificate map. Keep this state separate from
the disposable control-plane stack.

The certificate uses DNS authorization, so Google can issue and renew it before
a GKE Gateway exists. The control-plane Gateway later attaches the certificate
map and static IP from this stack.

## Prerequisites

- The Cloud DNS zone already exists and is publicly delegated from its parent
  zone. It must contain `events_domain`.
- Service Usage, Cloud DNS, Compute Engine, and Certificate Manager APIs are
  enabled. Service Usage itself must be enabled before Terraform can enable the
  remaining APIs.
- The deployment identity has Compute, DNS, and Certificate Manager permissions
  from `iam-policies/gcp/02-terraform-deploy.md`.

## Deploy once

```bash
cd terraform/events-edge/gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars.
terraform init
terraform apply
```

Keep the generated DNS authorization CNAME record and this stack after a
control-plane teardown. Wait for the Certificate Manager certificate to become
`ACTIVE` before the first control-plane deployment:

```bash
gcloud certificate-manager certificates describe CERTIFICATE_NAME \
  --location global \
  --project YOUR_GCP_PROJECT \
  --format="get(managed.state)"
```

The control-plane stack reads this local state by default from
`../../events-edge/gcp/terraform.tfstate`. If the state lives elsewhere, pass
the address and certificate-map names through its `events_gateway_address_name`
and `events_certificate_map_name` variables.

Do not destroy this stack during ordinary control-plane rebuilds. Destroying it
releases the public IP and certificate foundation, so a later recreation must
wait for issuance again.
