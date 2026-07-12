#!/bin/bash
set -euo pipefail
echo "==> System setup and KVM configuration"

# Wait for cloud-init to finish so package installs don't conflict.
cloud-init status --wait || true

# Update system packages.
sudo dnf update -y

# Install utilities.
# --allowerasing replaces curl-minimal (AL2023 default) with full curl.
# amazon-ssm-agent is required for Session Manager access on private nodes.
sudo dnf install -y --allowerasing \
  jq \
  curl \
  unzip \
  iptables \
  iproute \
  procps-ng \
  amazon-ssm-agent

# Ensure SSM agent is enabled/running in the baked AMI.
sudo systemctl enable amazon-ssm-agent
sudo systemctl restart amazon-ssm-agent

# --- KVM / Firecracker prerequisites ---

# Ensure /dev/kvm exists and is accessible.
if [ ! -e /dev/kvm ]; then
  echo "WARNING: /dev/kvm not found. This instance may not support KVM."
  echo "Firecracker requires a bare-metal instance type (e.g. c6g.metal)."
fi

# Set permissions on /dev/kvm so the agent can use it.
# This udev rule persists across reboots.
sudo tee /etc/udev/rules.d/99-kvm.rules > /dev/null <<'EOF'
KERNEL=="kvm", GROUP="kvm", MODE="0666"
EOF

# Create kvm group if it doesn't exist.
getent group kvm > /dev/null || sudo groupadd kvm

# Enable IP forwarding (required for VM networking).
sudo tee /etc/sysctl.d/99-firework.conf > /dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF
sudo sysctl --system

echo "==> System setup complete"
