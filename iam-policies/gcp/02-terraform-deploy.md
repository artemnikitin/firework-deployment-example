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
