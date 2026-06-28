#!/bin/bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  jq curl unzip iptables iproute2 procps

# GCE Debian images provide the Google guest environment. Keep Cloud SDK
# repository management out of this image to avoid duplicate APT sources.
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' | sudo tee /etc/udev/rules.d/99-kvm.rules
sudo groupadd -f kvm

sudo tee /etc/sysctl.d/99-firework.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF
sudo sysctl --system

curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
