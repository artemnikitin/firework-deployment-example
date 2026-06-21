# GCP control plane

This stack creates separate events, registry, and controller Compute Engine
VMs. Events and registry use regional external passthrough Network Load
Balancers so TLS reaches the Go processes unchanged. State and rendered node
configs use native GCS. The VMs have no external IPs and use Cloud NAT for
outbound package and artifact downloads.

Before initialization:

1. This stack enables the required Google APIs itself via the
   `google_project_service.required` resources in `services.tf` (Cloud Resource
   Manager, Service Usage, Compute, IAM, IAP, Storage, Secret Manager, DNS,
   Certificate Manager, Service Networking, Logging, Monitoring). But Terraform
   cannot manage services until the **Service Usage** and **Cloud Resource
   Manager** APIs are themselves enabled on the project, so run the one-time
   bootstrap command below first. This matters in practice because Application
   Default Credentials set `quota_project_id` to the target project, so every
   Service Usage call Terraform makes is billed to that project; if Service
   Usage is off there the first apply fails with 403 `SERVICE_DISABLED` on the
   `google_project_service` resources. (`gcloud services enable` is not affected
   because it bootstraps Service Usage on its own.)
2. Create the `firework-gcp` Cloud DNS zone and delegate it from the parent
   zone. The zone is intentionally not managed here.
3. Create a dedicated versioned GCS Terraform-state bucket. Do not reuse the
   Firework state/config bucket.
4. Grant the Terraform identity (whatever principal runs `apply` — your user or
   a deploy service account) the roles it needs to manage this stack. At minimum:
   DNS Admin, Service Account User for the runtime service accounts, and
   **Project IAM Admin** (`roles/resourcemanager.projectIamAdmin`) or Owner.
   Project IAM Admin is required because the stack grants project-level
   `roles/logging.logWriter` and `roles/monitoring.metricWriter` to the runtime
   service accounts (`iam.tf`); without it the `google_project_iam_member`
   resources fail with 403 `The caller does not have permission` while reading
   the project IAM policy, even though the resource-scoped bucket/secret IAM
   bindings still succeed. If `apply` runs as a deploy service account, confirm
   the effective identity with `data "google_client_openid_userinfo"`; an
   `export GOOGLE_APPLICATION_CREDENTIALS=...` or
   `export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=...` in the shell silently makes
   Terraform run as a service account instead of your gcloud user. A deploy SA
   with `roles/storage.admin` + `roles/secretmanager.admin` + `roles/compute.admin`
   etc. but no Project IAM Admin is the classic case: every resource builds, only
   the project-level `google_project_iam_member` grants fail.
5. Build the Linux AMD64 control-plane binary. Terraform uploads this exact
   binary to the private control-plane GCS bucket before creating the VMs.

One-time bootstrap so the first apply can manage every other API. Run this once
per project before `terraform init`/`apply`:

```bash
gcloud services enable \
  serviceusage.googleapis.com cloudresourcemanager.googleapis.com \
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

If apply fails with 403 `The caller does not have permission` only on the
`google_project_iam_member` resources (project-level `logWriter`/`metricWriter`)
while bucket/secret IAM bindings succeed, the identity running `apply` lacks
Project IAM Admin — see prerequisite 4. Grant
`roles/resourcemanager.projectIamAdmin` (or Owner) to that principal, or run as a
user who already has it. A re-apply only helps in the rare case the role was
truly just granted and is still propagating.

The ACME certificate and all generated private material are present in
Terraform state. Protect the backend accordingly. Re-apply before the events
certificate expires and recreate the events VM so the process reloads it.

The events DNS-01 challenge checks record propagation against the resolvers in
`acme_recursive_nameservers` (default Google/Cloudflare public DNS) rather than
the operator's local resolver, which avoids `propagation: time limit exceeded
... i/o timeout` failures when the local/router DNS is slow or unreachable. Set
the variable to `[]` to fall back to the system resolver.

## Teardown

The state/config bucket (`var.state_bucket_name`, e.g. `firework-control-plane-state`)
has object versioning enabled and `force_destroy` defaults to `false`, so a plain
`terraform destroy` fails with `Error trying to delete bucket ... without
force_destroy set to true` while it still holds objects/versions. To tear the
stack down, flip `state_bucket_force_destroy` so Terraform purges all object
versions itself:

```bash
# Persist force_destroy=true into the bucket's state, then destroy.
terraform apply -var='state_bucket_force_destroy=true' -target=google_storage_bucket.state
terraform destroy -var='state_bucket_force_destroy=true'
```

The `apply` is mandatory and separate: `force_destroy` is read from *state* at
delete time, so `terraform destroy -var='state_bucket_force_destroy=true'` alone
does nothing — you must `apply` it into state first. Note versioning means an
emptied bucket can still hold *noncurrent* versions that block deletion.

Alternatively, purge the bucket out-of-band (handles all object versions) and let
destroy remove the now-empty bucket:

```bash
gcloud storage rm --all-versions --recursive "gs://firework-control-plane-state/**"
terraform destroy -var='state_bucket_force_destroy=true'
```

This is the backend-independent config bucket, not the Terraform state backend
bucket (`firework-tfstate-*`), so purging it is safe.

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
