# GCP data plane

This stack creates a private managed instance group of x86_64 Firework nodes,
Cloud NAT, an amd64 GCS image bucket, and a global HTTPS load balancer that
terminates TLS and forwards HTTP to Traefik on port 8080.

Prerequisites:

- Build the `firework-node-gcp` image family with `packer/gcp`.
- Apply `terraform/control-plane/gcp` and copy its outputs into `terraform.tfvars`.
- Create and delegate the pre-existing Cloud DNS zone.
- Grant the Terraform service account Service Account User on the node runtime
  service account.
- Create a separate GCS Terraform-state bucket.

The default node count is three because the six demo services request 18 vCPUs
and each `n2-standard-8` node provides 8 vCPUs. Use four nodes for N+1 capacity.
Verify the selected Intel machine family supports nested virtualization in the
chosen zone before applying.

```bash
cd terraform/data-plane/gcp
cp terraform.tfvars.example terraform.tfvars
terraform init \
  -backend-config="bucket=firework-tfstate-YOUR_PROJECT" \
  -backend-config="prefix=data-plane/gcp"
terraform validate
terraform apply
```

Certificate Manager issuance commonly takes 15–60 minutes after DNS
authorization propagates. Nodes have no external IP; use IAP for SSH.
