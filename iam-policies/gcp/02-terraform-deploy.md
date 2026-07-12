# Terraform deployment principal

The demo stacks require permissions to manage Compute Engine networks,
instances and load balancers; GCS buckets and IAM; Secret Manager secrets;
Cloud DNS; Certificate Manager; GKE clusters; service accounts; logging
metrics; and monitoring resources. Typical predefined roles are:

- `roles/compute.admin`
- `roles/container.admin` — create and manage GKE Autopilot clusters (GCP control-plane)
- `roles/storage.admin`
- `roles/secretmanager.admin`
- `roles/dns.admin`
- `roles/certificatemanager.editor`
- `roles/iam.serviceAccountAdmin`
- `roles/iam.serviceAccountUser` — project-level for the first apply, so Terraform can attach its newly-created node service account
- `roles/serviceusage.serviceUsageAdmin` — enable APIs managed by Terraform
- `roles/resourcemanager.projectIamAdmin` — grant project-level `logWriter`/`metricWriter` to runtime SAs
- `roles/logging.configWriter`
- `roles/monitoring.editor`

Grant `roles/iam.serviceAccountUser` at project level before the first apply so
Terraform can attach the runtime node service account it creates in that same
apply. You can narrow this binding after bootstrap if you pre-create the service
account and manage its resource-level policy separately.

Terraform state is local in the example stacks. Protect the local state files;
when demo secret generation is enabled, they contain generated private keys and
bootstrap tokens. Operator-provided Secret Manager values are mounted through
CSI and are not read into Terraform state.

## Granting via CLI

Grant the identity Terraform authenticates as — your user account when using
`gcloud auth application-default login`, or the service account referenced by
`GOOGLE_APPLICATION_CREDENTIALS`. Confirm it with `gcloud config get-value
account`.

Project-level roles:

```bash
PROJECT_ID=your-project
PRINCIPAL="user:you@example.com"   # or serviceAccount:NAME@PROJECT_ID.iam.gserviceaccount.com

for role in \
  roles/compute.admin \
  roles/container.admin \
  roles/storage.admin \
  roles/secretmanager.admin \
  roles/dns.admin \
  roles/certificatemanager.editor \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/serviceusage.serviceUsageAdmin \
  roles/resourcemanager.projectIamAdmin \
  roles/logging.configWriter \
  roles/monitoring.editor; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$PRINCIPAL" --role="$role"
done
```

IAM changes can take up to a minute to propagate.

## Granting via Console

- Project roles: **IAM & Admin → IAM**
  (`console.cloud.google.com/iam-admin/iam`), edit the principal's row or
  **+ GRANT ACCESS**, then **+ ADD ANOTHER ROLE** for each role above.
