#!/bin/bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  ca-certificates gnupg jq curl unzip iptables iproute2 procps

# N4 instances require gVNIC. Fail the image build if the Debian cloud kernel
# does not provide the driver that the image advertises to Compute Engine.
sudo modprobe gve

# The Google guest environment does not include the Cloud SDK. Node startup
# uses gcloud to read Secret Manager and GCS, so bake the CLI into the image.
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
sudo apt-get update -y
sudo env CLOUDSDK_SKIP_PY_COMPILATION=1 apt-get install -y --no-install-recommends google-cloud-cli

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' | sudo tee /etc/udev/rules.d/99-kvm.rules
sudo groupadd -f kvm

sudo tee /etc/sysctl.d/99-firework.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF
sudo sysctl --system

curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
