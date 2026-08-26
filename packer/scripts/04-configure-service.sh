#!/bin/bash
set -euo pipefail
echo "==> Configuring firework-agent service"

# Create directories.
sudo mkdir -p /var/lib/firework
sudo mkdir -p /var/lib/images
sudo mkdir -p /etc/firework

# Create a placeholder agent config.
# The real provider-specific config is written by instance startup metadata.
sudo tee /etc/firework/agent.yaml > /dev/null <<'EOF'
# This file is overwritten by user data at instance launch.
# See terraform/data-plane/<provider>/templates/ for the templates.
node_names:
  - "unconfigured"
store_type: "s3"
s3_bucket: "unconfigured"
poll_interval: "30s"
firecracker_bin: "/usr/bin/firecracker"
state_dir: "/var/lib/firework"
log_level: "info"
api_listen_addr: ":8081"
enable_health_checks: true
enable_network_setup: true
EOF

# Create systemd service.
sudo tee /etc/systemd/system/firework-agent.service > /dev/null <<'EOF'
[Unit]
Description=Firework Agent - MicroVM Orchestrator
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/firework-agent --config /etc/firework/agent.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535
LimitNPROC=65535

# Volume work runs mkfs.ext4, e2fsck, and resize2fs as child processes, and the
# agent deliberately detaches them from its own shutdown so a restart or drain
# cannot interrupt a resize partway through. systemd's default
# KillMode=control-group defeats that: it signals every process in the cgroup,
# including the detached utility, and force-kills the group at TimeoutStopSec.
#
# KillMode=mixed sends SIGTERM to the agent only. TimeoutStopSec must stay above
# the agent's destructive-command deadline (destructiveCommandTimeout, 30m in
# internal/volume) plus its grace period, or systemd kills the utility anyway.
# See docs/persistent-volumes.md in the firework repository.
KillMode=mixed
TimeoutStopSec=2100

# Security hardening
NoNewPrivileges=no
ProtectSystem=false

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (it will start on boot after user data writes the real config).
sudo systemctl daemon-reload
sudo systemctl enable firework-agent

echo "==> Service configuration complete"
