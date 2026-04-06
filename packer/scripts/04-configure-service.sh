#!/bin/bash
set -euo pipefail
echo "==> Configuring firework-agent service"

# Create directories.
sudo mkdir -p /var/lib/firework
sudo mkdir -p /var/lib/images
sudo mkdir -p /etc/firework

# Create a placeholder agent config.
# The real config is written by the EC2 user data script at boot time,
# which fills in node_name, s3_bucket, and s3_region.
sudo tee /etc/firework/agent.yaml > /dev/null <<'EOF'
# This file is overwritten by user data at instance launch.
# See terraform/data-plane/templates/user-data.sh.tpl for the template.
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
