# GCP node image

This template builds an x86_64 Debian 12 image in the `firework-node-gcp`
image family. The builder uses an ephemeral external IP and does not depend on
the data-plane VPC.

Prerequisites: Packer, Application Default Credentials, Compute Engine API, and
a principal with Compute Instance Admin, Service Account User, and OS Login.

```bash
cd packer/gcp
cp firework-node-gcp.auto.pkrvars.hcl.example firework-node-gcp.auto.pkrvars.hcl
packer init .
packer validate .
packer build .
```

For a private build network, configure Cloud NAT and IAP separately; do not use
the data-plane VPC because it is created after the Packer phase.
