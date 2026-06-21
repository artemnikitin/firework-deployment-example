# Packer build principal

Grant the Packer principal:

- `roles/compute.instanceAdmin.v1`
- `roles/iam.serviceAccountUser`
- `roles/iap.tunnelResourceAccessor`
- `roles/compute.osAdminLogin`

The default demo builder uses an ephemeral external IP. IAP permissions become
active when a hardened private build VPC is configured.

## Why OS Login

The builder sets `use_os_login = true`, so Packer SSHes into the build VM via
OS Login. GCP only provisions a Linux (POSIX) account for identities that hold
`roles/compute.osLogin` (or its superset `roles/compute.osAdminLogin`). Without
it the build fails early with:

```
Error importing SSH public key for OSLogin: no PosixAccounts available
```

Grant the role to the **identity Packer actually authenticates as** — your user
account when using `gcloud auth application-default login`, or the service
account referenced by `GOOGLE_APPLICATION_CREDENTIALS`. Confirm it with
`gcloud config get-value account`.

## Using a dedicated build service account (impersonation)

To build as a dedicated SA (e.g. `firework-infra`) instead of your user, set the
builder's `impersonate_service_account` variable — the OS Login POSIX account is
then resolved for the **impersonated** SA, so that SA (not your user) needs
`roles/compute.osAdminLogin`:

```hcl
# firework-node-gcp.auto.pkrvars.hcl
impersonate_service_account = "firework-infra@PROJECT_ID.iam.gserviceaccount.com"
```

Your base ADC identity needs `roles/iam.serviceAccountTokenCreator` on that SA.

> The Packer `googlecompute` plugin does **not** read the
> `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` environment variable (that is a Terraform
> google-provider convention). For Packer, impersonation must be set via the
> `impersonate_service_account` HCL field.

## Granting via CLI

User account:

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:you@example.com" \
  --role="roles/compute.osAdminLogin"
```

Service account:

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:NAME@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.osAdminLogin"
```

Repeat `--role=...` for each role listed above. IAM changes can take up to a
minute to propagate; if a build still fails immediately, wait and retry.

## Granting via Console

1. Select the correct project (must match `gcp_project` in the pkrvars file).
2. **IAM & Admin → IAM** (`console.cloud.google.com/iam-admin/iam`).
3. Edit the row for your principal, or click **+ GRANT ACCESS** and enter it
   under **New principals**.
4. **+ ADD ANOTHER ROLE**, filter for `Compute OS Admin Login`, select it.
5. **Save**, then wait ~30–60s for propagation.
