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
