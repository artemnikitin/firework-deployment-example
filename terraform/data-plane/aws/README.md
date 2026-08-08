# Infra Terraform Stack

This stack provisions the data plane with Firework.

It creates:

- VPC with public/private subnets across two AZs
- S3 gateway VPC endpoint for image, config, and package traffic
- NAT gateways, only when nodes are placed in private subnets
- ALB (HTTPS) forwarding to Traefik on Firework nodes
- Node security groups and IAM role
- Launch template + Auto Scaling Group for Firework nodes

This stack depends on:

- AMI from [packer/aws/README.md](../../../packer/aws/README.md)
- Config bucket outputs from [terraform/control-plane/aws/README.md](../../control-plane/aws/README.md)
- Existing images bucket managed outside this stack

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- AWS credentials with permissions for VPC, EC2, ALB, IAM
- Control-plane stack already applied
- This stack always auto-wires config, registry, and bootstrap-token values from
  `../../control-plane/aws/terraform.tfstate` (`control_plane_state_path` can
  point elsewhere). The control-plane state must exist before this stack is
  planned or applied; duplicate manual overrides are intentionally not supported.
  If that state is unavailable, restore or relocate the control-plane state before
  planning this stack; there is no manual-wiring recovery path.
- Existing S3 images bucket and ARN
- Firework node AMI source (explicit ID, name pattern lookup, or Packer manifest)

Apply order is strict: deploy `terraform/control-plane/aws` first, then `terraform/data-plane/aws`.

## Cost, node placement, and node instance type

This is a demo stack, and the defaults are tuned to keep an idle deployment
cheap rather than to model a production topology. Read this section before
copying the network layout into anything real.

### Node network placement

`node_network_placement` controls where Firecracker nodes run.

| Value | Egress path | NAT gateways | Notes |
| --- | --- | --- | --- |
| `public` (default) | Internet gateway | none | Cheapest at demo scale |
| `private` | NAT gateway | 1 or 2 | Previous behaviour |

Internet gateway egress has no hourly or per-GB processing charge, so `public`
placement removes the NAT gateway line from the bill entirely. The cost becomes
one public IPv4 address per node, billed per address-hour.

**`public` placement has real security consequences. They are not theoretical:**

- **Source/destination check is disabled on these nodes.** It is turned off in
  user-data because east-west microVM traffic between nodes needs VPC routing to
  work. On a private subnet the blast radius is the VPC. On a public subnet with
  an internet gateway route, a node can emit packets with arbitrary source
  addresses directly to the internet.
- **The security group becomes the only inbound barrier.** Private subnets give
  a structural "no inbound from the internet" guarantee that does not depend on
  security group correctness. In `public` placement a single loosened rule in
  the node security group exposes a Firecracker host directly. The shipped rules
  allow only the Traefik port from the ALB security group and intra-VPC traffic.
- **Egress addresses are not stable.** NAT gateways have fixed Elastic IPs that
  can be allowlisted by external services. Public node addresses change on every
  instance replacement.
- **Cost crossover.** Public IPv4 charges scale with `node_count` while NAT
  gateway hours are flat. `public` stops being the cheaper option somewhere in
  the high teens of nodes.

Use `node_network_placement = "private"` for anything beyond a demo.

### NAT gateway topology

When placement is `private`, `nat_gateway_mode` controls the topology:

- `per_az` (default) — one gateway per AZ. Node egress survives a single-AZ
  failure.
- `single` — one gateway for all private subnets. Cheaper, but introduces an AZ
  dependency and cross-AZ data charges for non-S3 egress from the other zones.

Collapsing to a single AZ entirely is not available: the ALB requires at least
two availability zones.

### Changing availability zones

`availability_zones` accepts any number of zones from two upwards, in any order,
and the list can be edited later.

Subnets are keyed by availability zone, and each zone's CIDR is derived from the
trailing zone letter rather than from the zone's position in the list:

| Zone | Public | Private |
| --- | --- | --- |
| `<region>a` | `10.0.0.0/24` | `10.0.100.0/24` |
| `<region>b` | `10.0.1.0/24` | `10.0.101.0/24` |
| `<region>c` | `10.0.2.0/24` | `10.0.102.0/24` |

So adding or removing a zone only creates or destroys that zone's subnets and
leaves every other zone untouched. Reordering the list changes nothing at all.

The zone count is independent of `node_count`. The Auto Scaling Group spreads
however many nodes you ask for across whatever zones exist; you can run one node
across four zones, or four nodes across two.

**Two zones is the minimum**, enforced by a variable validation. This is an AWS
constraint rather than a limitation of this stack: an Application Load Balancer
requires subnets in at least two availability zones, and the ALB lives in these
subnets. A single-zone deployment would need the ALB to be given its own
subnets, separate from the node subnets.

Zone names must be of the standard `<region><letter>` form with a letter in
`a`-`h`. Local Zone and Wavelength names such as `us-east-1-bos-1a` are rejected,
because their trailing letter would collide with the ordinary zone of the same
letter.

### S3 gateway endpoint

An S3 gateway VPC endpoint is created in both placements and associated with the
public and private route tables. Gateway endpoints have no hourly charge.

It carries the rootfs image sync, S3 configuration polling, and `dnf` traffic
during bootstrap, since Amazon Linux package repositories are served from
regional S3. In `private` placement this removes that traffic from NAT data
processing charges; in `public` placement it keeps the traffic on the AWS
network rather than saving money.

**Gateway endpoints only serve buckets in the same region as this VPC.** The
images and configs buckets come from the control-plane stack, which has its own
region variable. A split-region deployment silently bypasses the endpoint with
no error and no failure — traffic just keeps taking the public path.

To verify the endpoint is carrying traffic in `private` placement, watch the NAT
gateway `BytesOutToDestination` CloudWatch metric during a node launch. It
should stay near flat instead of spiking by the size of the rootfs image set. In
`public` placement there is no NAT metric to watch; confirm instead that the S3
prefix-list route is present on the route table serving the node subnets.

### Node instance type and architecture

`node_instance_type` defaults to `c8i.2xlarge` with
`node_nested_virtualization = true`.

Firecracker needs `/dev/kvm`. Until AWS added nested virtualization on virtual
instances, that meant bare metal — and the smallest available Graviton metal SKU
is 64 vCPU, so the demo had to buy 64 vCPU regardless of what it actually ran.
Nested virtualization removes that floor: the node can be sized to the workload.
The saving is roughly six times on instance hours, which dominates the bill for
this stack.

Nested virtualization is supported on Intel families only — C8i, M8i, R8i and
their `id`/`flex` variants, X8i, C7i, M7i, R7i, C7i-flex, M7i-flex, I7i. It is
not supported on Graviton.

The default is an 8th-generation type deliberately. The AWS user guide lists
both 7th and 8th generation, but the Terraform provider documentation for
`cpu_options.nested_virtualization` describes 8th generation "only". The AWS
guide governs what the API accepts, so 7th-generation types should work — but
defaulting to 8th generation means the configuration does not depend on which
document is stale. Verify with `aws ec2 run-instances --dry-run --cpu-options`
before switching to a 7th-generation type.

Avoid the `flex` variants for nodes. They are designed for workloads that do not
sustain high CPU, which is the opposite of a Firecracker host.

Newer instance families are offered in fewer availability zones. If you pin
`availability_zones`, confirm the chosen type is actually offered in all of them:

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values=c8i.2xlarge \
  --region us-east-1 \
  --query 'InstanceTypeOfferings[].Location' --output text
```

AWS recommends bare metal for hardware-virtualization workloads that are
performance sensitive or have strict latency requirements, so **do not use this
stack to benchmark microVM boot latency.**

To go back to bare-metal Graviton nodes, three settings must change together,
plus the AMI and the image bucket:

```hcl
node_instance_type         = "c6g.metal"
node_nested_virtualization = false   # metal exposes /dev/kvm natively
node_ami_architecture      = "arm64"
```

and rebuild the AMI with `architecture = "arm64"` (see
[packer/aws/README.md](../../../packer/aws/README.md)) and point
`s3_images_bucket_id` at the arm64 rootfs bucket. Host and guest architecture
must match; a mismatch fails at microVM start, not at deploy time.

**Delete or rebuild `packer/aws/manifest.json` when switching architecture.**
`use_packer_manifest_ami` defaults to `true`, so a stale manifest left over from
a previous build resolves an AMI of the old architecture into an instance type
of the new one. That fails at instance launch with an unhelpful error rather
than at plan time.

This stack requires AWS provider `~> 6.33`, because
`cpu_options.nested_virtualization` on `aws_launch_template` was added there.

### Upgrading an existing deployment

The defaults in this stack changed: nodes moved from private subnets behind NAT
to public subnets, and from bare-metal Graviton to x86_64 with nested
virtualization. **An existing deployment on the old defaults must not simply
`apply` the new ones.**

The hazard is specific. Changing `vpc_zone_identifier` on an Auto Scaling Group
updates the group, but AWS does not reconfigure instances that are already
running. In the same apply, the NAT gateways and the private-subnet default
routes are deleted. Without an instance refresh, the already-running nodes stay
in the private subnets with no route to the internet and lose S3, EC2, Secrets
Manager, and registry access.

The ASG now sets `instance_refresh`, and pins `launch_template.version` to the
concrete `latest_version` rather than `$Latest`, because a refresh does not
start when the group references `$Latest`. Any launch-template change therefore
rolls the nodes. Note the refresh is asynchronous: AWS starts it, Terraform does
not block until it finishes, so old instances can briefly lose egress while
being replaced.

**The safe upgrade path is to pin the old behaviour first**, apply, and migrate
deliberately afterwards:

```hcl
node_network_placement     = "private"
nat_gateway_mode           = "per_az"
node_instance_type         = "c6g.metal"
node_nested_virtualization = false
node_ami_architecture      = "arm64"
```

That reproduces the previous topology exactly, so the upgrade is a no-op. Change
them one at a time when you are ready, and expect nodes to be replaced.

Switching architecture additionally requires rebuilding the AMI and repointing
`s3_images_bucket_id` at a matching rootfs image set, as described above.

#### Subnet keys changed from index to availability zone

Subnets, private route tables, and route-table associations moved from
positional `count` addresses to `for_each` keyed by availability zone. On an
already-applied stack the state addresses must be moved, for example:

```bash
terraform state mv 'aws_subnet.public[0]'  'aws_subnet.public["us-east-1a"]'
terraform state mv 'aws_subnet.private[0]' 'aws_subnet.private["us-east-1a"]'
# ... and the same for aws_route_table.private and both
#     aws_route_table_association resources
```

**Moving the state is not sufficient on its own.** CIDRs are now derived from
the zone letter, so any zone whose letter position differs from its old list
index also changes CIDR, and a CIDR change replaces the subnet. For a stack
originally applied with `["us-east-1a", "us-east-1c"]`, zone `a` keeps
`10.0.0.0/24` and is untouched, while zone `c` moves from `10.0.1.0/24` to
`10.0.2.0/24` and is replaced along with anything in it.

Because this is a one-time renumbering, the simplest path is to apply this
change to a destroyed stack. If the stack must stay up, expect the state moves
*plus* replacement of the subnets whose CIDR shifts.

### Node bootstrap network readiness

Instances can start while egress routes, NAT gateways, and the S3 endpoint are
still converging. The ASG waits for route-table associations and the S3 gateway
endpoint, and node user-data additionally waits for the regional EC2 endpoint
before doing metadata or storage setup. It then retries AWS API, S3, Secrets Manager,
and package calls with bounded exponential backoff. This keeps a
transient network timeout from making cloud-init's one-shot bootstrap fail
permanently. The launch template gzip-compresses user-data before base64
encoding so the complete bootstrap remains within EC2's 16 KiB raw-payload
limit; Amazon Linux cloud-init expands it before execution.

## Minimal Input (quick start)

With control-plane auto-wiring enabled, the minimum required `terraform.tfvars` values are:

- `domain_name`
- `s3_images_bucket_id`
- `s3_images_bucket_arn`
- `node_key_name`

`node_ami_id` is optional when one of these AMI auto-resolution paths is available.

## Routing domain

`domain_name` is the single source of truth for the wildcard ACM certificate and
the agent's `ingress_domain`. The data plane passes `domain_name` into each
node's `/etc/firework/agent.yaml` as `ingress_domain`, so a service whose GitOps
metadata sets `subdomain: tenant-1` is served at `tenant-1.<domain_name>`. The
wildcard certificate covers a single label (`*.<domain_name>`), so
`metadata.subdomain` must be exactly one label.

## Node AMI resolution

Node AMI is resolved in this priority order:

1. `node_ami_id` (explicit override)
2. `node_ami_name_pattern` (latest matching AMI in AWS)
3. `packer_manifest_path` (latest AMI for `aws_region` from `packer/aws/manifest.json` when `use_packer_manifest_ami = true`)

Notes:

- For `node_ami_name_pattern`, you can pass a partial name (for example `firework-node`); Terraform automatically searches as `*firework-node*`.
- Pattern lookup uses owners from `node_ami_owners` (default `["self"]`) and architecture `node_ami_architecture` (default `x86_64`).

## Node certificate bootstrap

AWS nodes use the registry bootstrap-token enrollment path. The data plane
reads `registry_url`, `registry_server_name`,
`registry_client_ca_secret_arn`, and `registry_bootstrap_token_secret_arn`
from the control-plane state and passes them to user-data. The node downloads
the trust root and token from Secrets Manager, enrolls directly with the
registry, and then uses the issued mTLS certificate for register/heartbeat
traffic. The shared bootstrap token is a demo trade-off; restrict it with
`registry_bootstrap_node_id` when practical.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Observability

This stack now provisions basic runtime observability:

- CloudWatch dashboard for node + ALB signals
- CloudWatch log groups for `firework-agent` and Firecracker VM logs
- ALB access logs in an S3 bucket when `enable_alb_access_logs = true` (the default)
- CloudWatch metric filters for common `firework-agent` error patterns
- CloudWatch metric filters for controller errors that read `/ecs/<project>/controlplane-controller` (created by the control-plane stack)

## Debugging

Whatever `node_network_placement` is set to, all node access goes through AWS Systems Manager Session Manager — no SSH, no bastion.

### Connect to a node

```bash
# Get the instance ID
terraform output -json node_instance_ids

# Open a shell
aws ssm start-session --target <instance-id>
```

### Check agent status

```bash
systemctl status firework-agent
```

### Follow agent logs

```bash
# Stream live
journalctl -u firework-agent -f

# Last 100 lines
journalctl -u firework-agent -n 100 --no-pager
```

Key things to look for in logs:
- `microVM started` — VM launched successfully
- `microVM exited cleanly` shortly after start — crash loop; check images and network config
- `linked service not found or has no network` — a service has `network: false` or is missing; check tenant YAML
- `reconciliation plan creates=N updates=N deletes=N` — agent picked up new config from S3

### Check agent config and images

```bash
# Confirm agent config looks correct (node_names, s3_bucket/s3_prefix, registry_url)
cat /etc/firework/agent.yaml

# Confirm all expected rootfs images are downloaded
ls -lh /var/lib/images/
```

### Query the agent API

The agent exposes a local HTTP API on port 8081:

```bash
# Overall status: running services, health, last revision
curl -s localhost:8081/status | jq .

# Health check results per service
curl -s localhost:8081/health | jq .

# Liveness probe
curl -s localhost:8081/healthz

# Prometheus-style runtime metrics (reconcile/image sync/config freshness)
curl -s localhost:8081/metrics
```

### Check running microVMs

```bash
# List active Firecracker processes
ps aux | grep firecracker

# List VM state directories
ls /var/lib/firework/vms/
```

### Check ALB target group health

Run this outside the node (from your workstation) to see what the ALB sees:

```bash
# List target groups
aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,`trafk`)].{Name:TargetGroupName,Arn:TargetGroupArn}' --output table

# Check health of a specific target group
aws elbv2 describe-target-health --target-group-arn <arn>
```

### Fast debug deploy of agent binary (no AMI rebuild)

From `firework-deployment-example/`, deploy a local binary to an existing node via SCP tunneled over SSM:

```bash
./scripts/push-agent-to-node.sh \
  --instance-id <instance-id> \
  --agent-path ../firework/bin/firework-agent-linux-amd64 \
  --ssh-key ~/.ssh/<your-key>.pem \
  --region us-east-1
```

Notes:
- Requires SSH over SSM (`AWS-StartSSHSession`) and a valid node key pair.

## Multi-node routing

The ALB uses a single target group containing all nodes. Traefik on each node
handles routing for both its own locally-scheduled services and services scheduled
on peer nodes.

For remote services, the agent reads all rendered node configs from S3, and for
each peer service that has a `metadata.host` and at least one `port_forwards` entry,
it writes a `remote-{service}.yaml` Traefik dynamic config file that proxies requests
to the peer node's host IP and forwarded port. Traefik watches the directory and picks
up the change without a reload.

This means a request that the ALB round-robins to any node will be correctly proxied
to the node where the target service is actually scheduled.

Remaining constraints:
- Remote routing requires `host_ip` to be populated in the peer node's rendered config
  (set automatically from the registry when nodes send heartbeats).
- The remote service must have at least one `port_forwards` entry so the host-side port
  is known.

## Persistent storage

Both storage backends are disabled by default:

- `enable_local_storage=true` attaches a separate encrypted gp3 disk with
  `delete_on_termination=false`. Startup formats only a blank device, mounts it
  by UUID at `/var/lib/firework/volumes`, and renders the configured logical
  admission budget. Startup tags the disk with `FireworkNodeID=<instance-id>`
  for recovery. ASG replacement leaves the old disk detached and the old
  node binding pending; it is never auto-attached to a replacement instance.
- `enable_shared_storage=true` creates encrypted Regional EFS, one mount target
  per node subnet, a node-only NFS security group, and an optional access
  point. Nodes mount it with TLS before the agent starts and verify a stable
  backend marker. Shared application placement remains safety-gated in
  Firework until durable per-VM fencing is available.

Application quota changes resize only the retained ext4 image. Expand the gp3
disk or adjust the EFS admission budget separately before retrying a quota
growth. Back up data before any shrink.

Local disks and EFS are intentionally retained. Inspect detached local disks
without changing them:

```bash
./scripts/cleanup-orphaned-aws-volumes.sh \
  --region us-east-1 \
  --project-name firework-demo \
  --config-bucket firework-demo-configs-example \
  --config-prefix cp/v1/
```

For a deliberate clean data-plane teardown that also permanently deletes
matching unattached local disks and retained local-volume records bound to
instances that no longer exist, run this from the repository root:

```bash
./scripts/destroy-aws-data-plane.sh \
  --region us-east-1 \
  --project-name firework-demo \
  -- -auto-approve
```

The cleanup scripts are deliberately dry-run by default. The destroy wrapper
captures the config bucket and prefix before Terraform removes the data-plane
outputs, then passes the explicit `--delete` flag only after a successful
destroy. Active or stopped EC2 bindings are never selected. This keeps a later
fresh provision from inheriting a binding to a deleted instance without
weakening Firework's fail-closed behavior for ordinary node loss. EFS is not
included in this cleanup. EFS has Terraform `prevent_destroy`; for
deliberate stack teardown, first destroy its access point/mount targets/security
group, remove the EFS resource from Terraform state so it remains retained,
then destroy the rest. Delete the file system manually only after a backup and
explicit data-retention decision.

## Destroy

Use the wrapper above when local persistent storage and its logical bindings
should be deleted with the data plane. Use `terraform destroy` directly when
retained disks and bindings must be preserved for explicit recovery.
