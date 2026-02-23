# Firework Deployment Example

Reference deployment of [Firework](https://github.com/artemnikitin/firework) on AWS using Packer + Terraform.

This root README stays intentionally high level. Detailed instructions live next to each stack.

## Architecture

```
                   ┌──────────────────────────────────────────────────────────┐
                   │                           VPC                            │
GitHub ──webhook──>│  API GW --> Enricher Lambda --> S3 (configs)            │
                   │                                        ^                 │
CI ---- rootfs --->│                                S3 (images)               │
                   │                                  ^     │                 │
                   │  ┌──── Public subnets ──────┐    │     │                 │
                   │  │    ALB :443 (HTTPS)       │    │     │                 │
                   │  └──────────┬────────────────┘    │     │                 │
                   │  ┌──────────v──── Private subnet ──────┤                 │
                   │  │    c6g.metal node (1x)               │                │
                   │  │    ├─ firework-agent                 │                │
                   │  │    ├─ tenant-1-kibana VM :5611 <─ALB│                │
                   │  │    ├─ tenant-1-elasticsearch VM :9200│                │
                   │  │    ├─ tenant-2-kibana VM :5612 <─ALB│                │
                   │  │    └─ tenant-2-elasticsearch VM :9200│                │
                   │  └──────────────────────────────────────┘                │
                   └──────────────────────────────────────────────────────────┘
```

## Deployment Flow

1. Build node AMI with Packer.
2. Deploy control-plane stack (creates webhook, Lambdas, config bucket).
3. Deploy infra stack (creates network, nodes, ALB).
4. Push configs/images and let the agent reconcile microVMs.

## Detailed Guides

- Packer AMI build: `packer/README.md`
- Control plane Terraform stack: `terraform/control-plane/README.md`
- Infra Terraform stack: `terraform/infra/README.md`

## Key Notes

- Deploy order matters: control-plane first, infra second.
- Nodes are in private subnets; use AWS Session Manager for access — no SSH exposed.
- ALB serves HTTPS (TLS 1.2/1.3) with host-based routing per tenant.
- Observability is managed as code in Terraform (dashboards, logs, access logs, metric filters).

## Cleanup

Destroy in reverse order:

```bash
cd terraform/infra && terraform destroy
cd ../control-plane && terraform destroy
```
