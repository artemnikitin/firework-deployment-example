# Firework Deployment Example

Reference deployment of [Firework](https://github.com/artemnikitin/firework) on AWS using Packer (for building AMI) + Terraform.

## Related repositories

- [firework](https://github.com/artemnikitin/firework) — The orchestrator itself
- [firework-gitops-example](https://github.com/artemnikitin/firework-gitops-example) — Example GitOps configuration repository

## Architecture

```mermaid
flowchart LR
  GitHub["GitHub (config repo)"] -->|push webhook| APIGW["API Gateway /webhook"]
  CI["CI pipeline"] -->|build + upload rootfs| S3Images["S3 images bucket"]

  subgraph VPC["AWS VPC"]
    direction LR

    subgraph ControlPlane["Control plane"]
      APIGW --> Enricher["Enricher Lambda"]
      Enricher -->|invoke| Scheduler["Scheduler Lambda"]
      Scheduler -->|placement| Enricher
      Enricher -->|write node configs| S3Configs["S3 configs bucket"]
      CloudWatch["CloudWatch metrics"] --> Scheduler
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
    Node -->|publish capacity| CloudWatch
    ALB -->|tenant traffic| Node
  end
```

## Deployment Flow

0. Make sure that you are using an AWS account with correct permissions to deploy all the resources. See `iam-policies` folder for more details.
1. Build AMI for EC2 instance(s) with Packer.
2. Deploy control-plane stack (creates webhook, Lambdas, config bucket).
3. Deploy infra and data-plane (creates network, EC2 instances, ALB, etc).
4. Push configs/images and let the agent reconcile microVMs.

## Detailed Guides

- Packer AMI build: [packer/README.md](packer/README.md)
- Control plane Terraform stack: [terraform/control-plane/README.md](terraform/control-plane/README.md)
- Infra and data plane Terraform stack: [terraform/infra/README.md](terraform/infra/README.md)

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
