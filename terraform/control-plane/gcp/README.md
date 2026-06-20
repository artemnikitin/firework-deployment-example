# GCP control plane

This stack creates separate events, registry, and controller Compute Engine
VMs. Events and registry use regional external passthrough Network Load
Balancers so TLS reaches the Go processes unchanged. State and rendered node
configs use native GCS. The VMs have no external IPs and use Cloud NAT for
outbound package and artifact downloads.

Before initialization:

1. Enable Compute, IAM, IAP, Storage, Secret Manager, DNS, Logging, and
   Monitoring APIs.
2. Create the `firework-gcp` Cloud DNS zone and delegate it from the parent
   zone. The zone is intentionally not managed here.
3. Create a dedicated versioned GCS Terraform-state bucket. Do not reuse the
   Firework state/config bucket.
4. Grant the Terraform service account DNS Admin and Service Account User for
   the runtime service accounts.
5. Build the Linux AMD64 control-plane binary. Terraform uploads this exact
   binary to the private control-plane GCS bucket before creating the VMs.

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
# From the shared parent directory containing both repositories:
make -C firework build-linux-amd64
```

```bash
cd firework-deployment-example/terraform/control-plane/gcp
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

## GitOps input root

GCP consumes the GitOps repository **root** as the enricher input. `config_dir`
defaults to `""` (the root) and no longer points at a provider-specific `gcp/`
hostname overlay — public routing is deployment-neutral via the agent
`ingress_domain` (derived from the data-plane `base_domain`).

Changing `config_dir` updates instance metadata but does not rewrite the running
events VM's `/etc/firework/controlplane.yaml`. After Terraform installs the new
startup-script metadata, restart or recreate the **events** VM so the startup
script rewrites the config and systemd loads `config_dir: ""`; a service restart
alone is insufficient if the file was not rewritten first. Inspect the plan to
avoid unnecessary registry/controller VM replacement. Because GCP does not set
`reconcile_on_start`, trigger a GitHub push/redelivery afterward — a process
restart by itself does not publish a new desired revision.
