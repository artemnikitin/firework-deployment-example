# CI image uploader

Grant the GitHub Actions service account `roles/storage.objectAdmin` on the
amd64 images bucket only. Do not grant the role at project level.

Use Workload Identity Federation and grant the repository principal
`roles/iam.workloadIdentityUser` on that service account. No JSON service
account key is required.

## Granting via CLI

Bucket-level upload access (note: bucket-scoped, not project-scoped):

```bash
gcloud storage buckets add-iam-policy-binding gs://AMD64_IMAGES_BUCKET \
  --member="serviceAccount:CI_SA@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

Workload Identity Federation binding for the GitHub repository principal:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  CI_SA@PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/attribute.repository/OWNER/REPO"
```

## Granting via Console

- Bucket access: **Cloud Storage → Buckets →** select the amd64 images bucket
  **→ Permissions → Grant access**, add the CI service account, role
  **Storage Object Admin**.
- WIF binding: **IAM & Admin → Service Accounts →** select the CI service
  account **→ Permissions → Grant access**, role **Workload Identity User**.
  Entering a `principalSet://` member is awkward in the Console — prefer the CLI
  for this one.
