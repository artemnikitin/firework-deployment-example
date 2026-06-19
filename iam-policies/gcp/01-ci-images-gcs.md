# CI image uploader

Grant the GitHub Actions service account `roles/storage.objectAdmin` on the
amd64 images bucket only. Do not grant the role at project level.

Use Workload Identity Federation and grant the repository principal
`roles/iam.workloadIdentityUser` on that service account. No JSON service
account key is required.
