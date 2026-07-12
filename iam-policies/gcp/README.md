# GCP IAM

The Terraform code grants runtime identities only the resource access they
need. In particular, Secret Manager accessor bindings are per secret:

| Runtime identity | Secret access |
|---|---|
| Node | Registry bootstrap token and enrollment/registry CA certificate |
| Events | Events TLS certificate/key and webhook secret |
| Registry | Registry TLS certificate/key, enrollment CA certificate/key, bootstrap token |
| Controller | None |

Never replace these with a project-wide Secret Manager accessor grant.

## Granting roles

The deploy/CI/Packer principal bindings in the files below are granted manually
(the runtime-identity bindings above are managed by Terraform). Two mechanisms:

- **Project-level** roles: **IAM & Admin → IAM** in the Console, or
  `gcloud projects add-iam-policy-binding PROJECT_ID --member=... --role=...`.
- **Resource-level** roles (buckets, service accounts): the resource's
  **Permissions** tab in the Console, or the resource-specific
  `gcloud storage buckets add-iam-policy-binding` /
  `gcloud iam service-accounts add-iam-policy-binding`.

Grant to the identity the tool actually authenticates as (user ADC vs. service
account); confirm with `gcloud config get-value account`. IAM changes can take
up to a minute to propagate. Each file below lists the concrete CLI and Console
steps for its principal:

- [`01-ci-images-gcs.md`](01-ci-images-gcs.md) — CI image uploader
- [`02-terraform-deploy.md`](02-terraform-deploy.md) — Terraform deploy
- [`03-packer-build.md`](03-packer-build.md) — Packer build
