# Packer build principal

Grant the Packer principal:

- `roles/compute.instanceAdmin.v1`
- `roles/iam.serviceAccountUser`
- `roles/iap.tunnelResourceAccessor`
- `roles/compute.osAdminLogin`

The default demo builder uses an ephemeral external IP. IAP permissions become
active when a hardened private build VPC is configured.
