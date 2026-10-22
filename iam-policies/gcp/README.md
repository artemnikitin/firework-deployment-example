# GCP IAM

The default `controlplane_service_mode = "all"` uses one control-plane service
account with mutating GCS state access. It can read the webhook secret, shared
listener TLS certificate/key, enrollment CA certificate/key, bootstrap and
operator tokens, and an optional GitHub token. The API runs under that same
identity.

Set `controlplane_service_mode = "split"` for separate role identities and a
read-only GCS identity for the API. Secret Manager accessor bindings are per
secret in both modes. The node identity is separate in either mode; the
role-specific rows below describe split mode:

| Runtime identity | Secret access |
|---|---|
| Node | Registry bootstrap token and enrollment/registry CA certificate |
| Events | Events TLS certificate/key, webhook secret, optional GitHub token |
| Registry | Registry TLS certificate/key, enrollment CA certificate/key, bootstrap token |
| Controller | None |
| API | Events TLS certificate/key and operator token |

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

Grant to the tool's effective identity; see [effective credentials](#effective-credentials).
IAM changes can take up to a minute to propagate. Each file below lists the
concrete CLI and Console steps for its principal:

- [`01-ci-images-gcs.md`](01-ci-images-gcs.md) — CI image uploader
- [`02-terraform-deploy.md`](02-terraform-deploy.md) — Terraform deploy
- [`03-packer-build.md`](03-packer-build.md) — Packer build

## Effective credentials

`gcloud auth list` and `gcloud config get-value account` show gcloud's own
account. They do not identify Terraform/Packer's Application Default
Credentials (ADC) or an impersonated service account.

Check explicit tool credentials and impersonation settings first, then the
`GOOGLE_APPLICATION_CREDENTIALS` file, local ADC created by
`gcloud auth application-default login`, or the attached service account.
Terraform also supports `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT`; Packer uses the
builder's `impersonate_service_account` field. When impersonating, grant the
deployment/build roles to the target service account and impersonation access
to the base identity. See [Google's ADC search order](https://docs.cloud.google.com/docs/authentication/application-default-credentials).
