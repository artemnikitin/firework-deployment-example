# Firework Deployment Example

> **Not production-ready.** This is an example deployment intended for demonstration and learning purposes only. It is not hardened, audited, etc.

Example AWS and GCP deployments of [Firework](https://github.com/artemnikitin/firework) using Packer and Terraform.

## Related repositories

- [firework](https://github.com/artemnikitin/firework) — The orchestrator itself
- [firework-gitops-example](https://github.com/artemnikitin/firework-gitops-example) — Example GitOps configuration repository

## AWS architecture

```mermaid
flowchart LR
  GitHub["GitHub (config repo)"] -->|push webhook| EventsALB["Events ALB :443"]
  CI["CI pipeline"] -->|build + upload rootfs| S3Images["S3 images bucket"]

  subgraph VPC["AWS VPC"]
    direction LR

    subgraph ControlPlane["Control plane (ECS/Fargate, role-separated)"]
      EventsALB --> Events["events service"]
      Events --> S3Configs["S3 configs/state bucket"]
      RegistryNLB["Registry NLB :9443"] --> Registry["registry service"]
      StepCANLB["step-ca NLB :9000 (optional)"] --> StepCA["step-ca service"]
      Registry --> S3Configs
      Controller["controller service"] --> S3Configs
    end

    subgraph Public["Public subnets"]
      ALB["ALB :443 (HTTPS)"]
    end

    subgraph Private["Private subnet"]
      Node["c6g.metal node<br/>firework-agent + Traefik"]
      VM1["tenant-1-kibana VM :5611"]
      VM2["tenant-1-elasticsearch VM :9200"]
      VM3["tenant-2-kibana VM :5612"]
      VM4["tenant-2-elasticsearch VM :9200"]

      Node --> VM1
      Node --> VM2
      Node --> VM3
      Node --> VM4
    end

    S3Configs -->|poll configs| Node
    S3Images -->|download rootfs| Node
    Node -- "AWS IID cert bootstrap (optional)" --> StepCANLB
    Node -->|mTLS enroll/register/heartbeat| RegistryNLB
    ALB -->|tenant traffic| Node
  end
```

## Deployment flow

1. Choose a provider and configure the permissions described in `iam-policies/<provider>`.
2. Build the node image with `packer/<provider>`.
3. Deploy `terraform/control-plane/<provider>`.
4. Deploy `terraform/data-plane/<provider>`.
5. Push configs/images and let the agent reconcile microVMs.

## Detailed Guides

- AWS: [Packer](packer/aws/README.md), [control plane](terraform/control-plane/aws/README.md), [data plane](terraform/data-plane/aws/README.md)
- GCP: [Packer](packer/gcp/README.md), [control plane](terraform/control-plane/gcp/README.md), [data plane](terraform/data-plane/gcp/README.md)

## Key Notes

- Deploy order matters: control-plane first, data-plane second.
- Nodes are in private subnets; use AWS Session Manager for access — no SSH exposed.
- ALB serves HTTPS (TLS 1.2/1.3); host-based routing per tenant is handled by Traefik on the nodes.
- Optional step-ca service can issue short-lived node certs via AWS IID instead of static bootstrap tokens.
- Observability is managed as code in Terraform (dashboards, logs, access logs, metric filters).

For GCP, the control-plane roles run on separate Compute Engine VMs behind
passthrough Network Load Balancers. The x86_64 data plane is a private managed
instance group using nested virtualization, Cloud NAT, GCS, and a global HTTPS
load balancer to Traefik. See the GCP guides above for DNS delegation and TLS
prerequisites.

## Cleanup

Destroy each provider in reverse order:

```bash
cd terraform/data-plane/aws && terraform destroy
cd ../../control-plane/aws && terraform destroy

cd terraform/data-plane/gcp && terraform destroy
cd ../../control-plane/gcp && terraform destroy
```
