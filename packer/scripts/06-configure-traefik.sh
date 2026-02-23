#!/bin/bash
# Configure Traefik reverse proxy as a systemd service.
# Called by Packer during AMI build.
set -euo pipefail

echo "==> Configuring Traefik"

# Directories: static config in /etc/traefik/, dynamic configs in dynamic/
# (the firework-agent writes per-service YAML files here at runtime).
sudo mkdir -p /etc/traefik/dynamic

# Static config.
# entryPoints.web listens on 8080 (ALB target group port).
# ping is enabled for ALB health checks at /ping.
# providers.file watches the dynamic/ subdirectory.
# User-data does NOT need to overwrite this file.
sudo tee /etc/traefik/traefik.yaml > /dev/null <<'EOF'
# Traefik static configuration — managed by Packer AMI build.
# The dynamic config directory is written by firework-agent at runtime.

entryPoints:
  web:
    address: ":8080"

ping:
  entryPoint: web

log:
  level: INFO
  filePath: /var/log/traefik.log

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
EOF

# Systemd service.
sudo tee /etc/systemd/system/traefik.service > /dev/null <<'EOF'
[Unit]
Description=Traefik Reverse Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/traefik --configFile=/etc/traefik/traefik.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535

# Traefik needs to bind to port 8080 — no special capability needed above 1024.
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log /etc/traefik/dynamic

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable traefik

echo "==> Traefik configuration complete"
