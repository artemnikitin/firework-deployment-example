# Terraform deployment principal

The demo stacks require permissions to manage Compute Engine networks,
instances and load balancers; GCS buckets and IAM; Secret Manager secrets;
Cloud DNS; Certificate Manager; service accounts; logging metrics; and
monitoring resources. Typical predefined roles are:

- `roles/compute.admin`
- `roles/storage.admin`
- `roles/secretmanager.admin`
- `roles/dns.admin`
- `roles/certificatemanager.editor`
- `roles/iam.serviceAccountAdmin`
- `roles/logging.configWriter`
- `roles/monitoring.editor`

Grant `roles/iam.serviceAccountUser` on each runtime service account so
Terraform can attach it to instances and templates. The ACME provider uses the
same Application Default Credentials and needs DNS Admin on the managed zone.

Restrict Terraform-state bucket `roles/storage.objectAdmin` to this principal.
That state contains private keys, certificates, webhook secrets, and bootstrap
tokens.

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
  roles/storage.admin \
  roles/secretmanager.admin \
  roles/dns.admin \
  roles/certificatemanager.editor \
  roles/iam.serviceAccountAdmin \
  roles/logging.configWriter \
  roles/monitoring.editor; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$PRINCIPAL" --role="$role"
done
```

`roles/iam.serviceAccountUser` on each runtime service account so Terraform can
attach it to instances and templates:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  RUNTIME_SA@PROJECT_ID.iam.gserviceaccount.com \
  --member="$PRINCIPAL" --role="roles/iam.serviceAccountUser"
```

Terraform-state bucket access (bucket-scoped, restricted to this principal):

```bash
gcloud storage buckets add-iam-policy-binding gs://TFSTATE_BUCKET \
  --member="$PRINCIPAL" --role="roles/storage.objectAdmin"
```

IAM changes can take up to a minute to propagate.

## Granting via Console

- Project roles: **IAM & Admin → IAM**
  (`console.cloud.google.com/iam-admin/iam`), edit the principal's row or
  **+ GRANT ACCESS**, then **+ ADD ANOTHER ROLE** for each role above.
- Per-service-account `Service Account User`: **IAM & Admin → Service
  Accounts →** select the runtime SA **→ Permissions → Grant access**.
- State bucket: **Cloud Storage → Buckets →** select the state bucket **→
  Permissions → Grant access**, role **Storage Object Admin**.
