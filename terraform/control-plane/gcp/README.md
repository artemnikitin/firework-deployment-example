# GCP control plane

This stack creates separate events, registry, and controller Compute Engine
VMs. Events and registry use regional external passthrough Network Load
Balancers so TLS reaches the Go processes unchanged. State and rendered node
configs use native GCS.

Before initialization:

1. Enable Compute, IAM, IAP, Storage, Secret Manager, DNS, Logging, and
   Monitoring APIs.
2. Create the `firework-gcp` Cloud DNS zone and delegate it from the parent
   zone. The zone is intentionally not managed here.
3. Create a dedicated versioned GCS Terraform-state bucket. Do not reuse the
   Firework state/config bucket.
4. Grant the Terraform service account DNS Admin and Service Account User for
   the runtime service accounts.

Enable the required APIs in a clean project:

```bash
gcloud services enable \
  compute.googleapis.com iam.googleapis.com iap.googleapis.com \
  storage.googleapis.com secretmanager.googleapis.com dns.googleapis.com \
  certificatemanager.googleapis.com servicenetworking.googleapis.com \
  logging.googleapis.com monitoring.googleapis.com \
  --project=YOUR_GCP_PROJECT
```

Create the Cloud DNS zone once and copy its exact assigned nameservers into
`terraform/dns-foundation`; nameserver shards are not stable and must not be
hardcoded. Verify delegation with `dig NS gcp.example.com +short`.

```bash
cd terraform/control-plane/gcp
cp terraform.tfvars.example terraform.tfvars
terraform init \
  -backend-config="bucket=firework-tfstate-YOUR_PROJECT" \
  -backend-config="prefix=control-plane/gcp"
terraform validate
terraform apply
```

The ACME certificate and all generated private material are present in
Terraform state. Protect the backend accordingly. Re-apply before the events
certificate expires and recreate the events VM so the process reloads it.
