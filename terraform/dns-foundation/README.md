# DNS foundation

Create the Cloud DNS zone manually, copy the exact four assigned nameservers
into `terraform.tfvars`, and apply this stack once. It delegates the GCP
subdomain from the Route53 parent zone and uses `prevent_destroy` so ordinary
control-plane or data-plane cleanup cannot remove the delegation.

Keep this state separate from disposable workload stacks. Verify propagation
with `dig NS gcp.example.com +short` before applying either GCP stack.
