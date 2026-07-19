# GCP node image

This template builds an x86_64 Debian 12 image in the `firework-node-gcp`
image family. It includes the Google Cloud CLI used at node startup to read
Secret Manager and GCS, plus `e2fsprogs` and `nfs-common` for persistent
storage pools. The builder uses an ephemeral external IP and does not
depend on the data-plane VPC.

Prerequisites: Packer, Application Default Credentials, Compute Engine API, and
a principal with Compute Instance Admin, Service Account User, and OS Login.

```bash
cd packer/gcp
cp firework-node-gcp.auto.pkrvars.hcl.example firework-node-gcp.auto.pkrvars.hcl
packer init .
packer validate .
packer build .
```

The built image declares gVNIC support and verifies the `gve` driver so it can
boot data-plane nodes on the default N4 machine type.

For a private build network, configure Cloud NAT and IAP separately; do not use
the data-plane VPC because it is created after the Packer phase.
