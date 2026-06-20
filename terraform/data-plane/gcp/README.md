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

## Routing domain

`base_domain` (for example `gcp.example.com`) is the single source of truth for
the wildcard DNS record, the Certificate Manager wildcard certificate, and the
agent's `ingress_domain`. The data plane passes `base_domain` into each node's
`/etc/firework/agent.yaml` as `ingress_domain`, so a service whose GitOps
metadata sets `subdomain: tenant-1` is served at `tenant-1.<base_domain>` (for
example `tenant-1.gcp.example.com`).

Because the wildcard certificate covers a single label (`*.<base_domain>`),
`metadata.subdomain` must be exactly one label. Do not introduce a separate
variable for the agent domain — a second value could drift from the domain used
by DNS and TLS.
