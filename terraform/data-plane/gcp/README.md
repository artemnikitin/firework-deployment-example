# GCP data plane

This stack creates a private managed instance group of x86_64 Firework nodes,
Cloud NAT, and a global HTTPS load balancer that
terminates TLS and forwards HTTP to Traefik on port 8080.

Terraform state is **local**. The stack auto-wires control-plane outputs from
the local control-plane state file by default.

Prerequisites:

- Build the `firework-node-gcp` image family with `packer/gcp`.
- Apply `terraform/control-plane/gcp`; the default local-state wiring reads its outputs automatically.
- Create and delegate the pre-existing Cloud DNS zone.
- Grant the Terraform principal `roles/iam.serviceAccountUser` at project scope
  before the first apply, so it can attach the node service account Terraform creates.

The default node count is three because the six demo services request 18 vCPUs
and each `n4-standard-8` node provides 8 vCPUs. N4 requires a Packer image
advertising gVNIC support plus Hyperdisk and gVNIC in the instance template.
Compute Engine selects its required NVMe disk interface automatically. Updates
create one replacement in each selected zone before old nodes are removed, so
ensure quota for three temporary surge nodes. Use four nodes for N+1 capacity.

Before changing an existing deployment to N4, confirm that the selected node
image declares the `GVNIC` guest OS feature. Images built by this Packer
configuration do. Applying this stack creates a new template and rolls every
node.

`node_zones` optionally overrides the regional MIG's zone placement. Any two or
more distinct zones of `gcp_region` are accepted, in any order, and the count is
independent of `node_count` — the regional MIG spreads whatever target size you
ask for across the zones you give it.

Leaving it `null` uses every zone the region currently reports as UP, discovered
via `google_compute_zones` rather than assumed. This matters: not every region
has a `-a` zone. `us-east1` and `europe-west1` both start at `-b`, so a
hardcoded `<region>-a` default fails outright there.

For a `us-central1` deployment, `us-central1-a`, `us-central1-b`, and
`us-central1-f` avoid the exhausted `us-central1-c` pool. Changing the zone set
replaces the regional MIG; Google does not support changing it in place.

Unlike AWS, zone changes here never renumber subnet CIDRs: a GCP subnetwork is
regional and spans every zone, so there is exactly one node subnet regardless of
how many zones are in use.

To move the data plane to another region, change `gcp_region`, either clear
`node_zones` or set zones of the new region, and use a new non-overlapping
`network_cidr`.
The MIG uses create-before-destroy so Terraform can switch the global backend
service to the replacement MIG before deleting the old one. The regional
subnet, Cloud NAT/router, MIG, and log buckets are recreated; the global tenant
IP, DNS record, and frontend remain managed in place.

```bash
cd terraform/data-plane/gcp
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform apply
```

Certificate Manager issuance commonly takes 15–60 minutes after DNS
authorization propagates. Nodes have no external IP; use IAP for SSH.

## Persistent storage

Storage remains disabled unless explicitly enabled:

- `enable_local_storage=true` adds a stateful Hyperdisk Balanced disk named
  `firework-volumes` to each instance. The regional MIG uses `delete_rule =
  "NEVER"`, preserves instance names with `RECREATE`, disables proactive zone
  redistribution, and uses an unavailable (non-surge) rollout. Startup formats
  only a blank disk and mounts it by UUID at `/var/lib/firework/volumes`.
- `enable_shared_storage=true` enables the Filestore API and creates a Regional
  NFSv4.1 share on the node VPC. Nodes mount it before the agent starts and
  verify the configured backend identity marker. The default 1 TiB capacity is
  a material cost; confirm tier/region minimums before applying. Shared
  application placement remains safety-gated until Firework's durable fencing
  work is complete.

Application quota resize affects only `volume.ext4`, not Hyperdisk or
Filestore capacity. Grow the provider backend separately and back up before
shrinking an application quota.

Stateful disks use `NEVER` and can remain after MIG deletion. Inspect matching
unattached Firework `pd-balanced` or `hyperdisk-balanced` local-storage disks
without changing them:

```bash
./scripts/cleanup-orphaned-gcp-volumes.sh \
  --project example-project \
  --deployment-name firework \
  --config-bucket firework-control-plane-state \
  --config-prefix cp/v1/
```

For a deliberate clean data-plane teardown that also permanently deletes
matching unattached local disks and retained local-volume records bound to
instances that no longer exist, run this from the repository root:

```bash
./scripts/destroy-gcp-data-plane.sh \
  --project example-project \
  --deployment-name firework \
  -- -auto-approve
```

The cleanup scripts are deliberately dry-run by default. The destroy wrapper
captures the config bucket and prefix before Terraform removes the data-plane
outputs, then passes the explicit `--delete` flag only after a successful
destroy. Bindings to existing Compute Engine instances are never selected.
This keeps a later fresh provision from inheriting a binding to a deleted MIG
instance without weakening Firework's fail-closed behavior for ordinary node
loss. Filestore deletion protection defaults to true; disable it only for
deliberate teardown.

## Routing domain

`base_domain` (for example `gcp.example.com`) is the single source of truth for
the wildcard DNS record, the Certificate Manager wildcard certificate, and the
agent's `ingress_domain`. The data plane passes `base_domain` into each node's
`/etc/firework/agent.yaml` as `ingress_domain`, so a service whose GitOps
metadata sets `subdomain: tenant-1` is served at `tenant-1.<base_domain>` (for
example `tenant-1.gcp.example.com`).

Because the wildcard certificate covers a single label (`*.<base_domain>`),
`metadata.subdomain` must be exactly one label. Do not introduce a separate
variable for the agent domain — a second value could drift from the domain used
by DNS and TLS.
