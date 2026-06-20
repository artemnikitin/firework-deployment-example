#!/bin/bash
# shellcheck disable=SC2154 # Terraform template variables are resolved before execution.
set -euo pipefail
umask 077

ROLE="${role}"
PROJECT="${gcp_project}"
CONTROLPLANE_BINARY_URI="${controlplane_binary_uri}"

apt-get update -y
apt-get install -y --no-install-recommends curl jq ca-certificates
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm -f add-google-cloud-ops-agent-repo.sh

gcloud storage cp "$CONTROLPLANE_BINARY_URI" /usr/local/bin/firework-controlplane
chmod 0755 /usr/local/bin/firework-controlplane

mkdir -p /etc/firework/tls
chmod 0700 /etc/firework /etc/firework/tls

read_secret() {
  gcloud secrets versions access latest --project="$PROJECT" --secret="$1"
}

case "$ROLE" in
  events)
    read_secret "${events_tls_cert_secret}" > /etc/firework/tls/server.crt
    read_secret "${events_tls_key_secret}" > /etc/firework/tls/server.key
    WEBHOOK_SECRET=$(read_secret "${webhook_secret}")
    cat > /etc/firework/controlplane.yaml <<EOF
role: events
events_listen_addr: ":443"
state:
  backend: gcs
  prefix: "${state_prefix}"
  gcs:
    bucket: "${state_bucket}"
    project: "$PROJECT"
leader_lease_ttl: "30s"
leader_renew_interval: "10s"
node_stale_ttl: "${node_stale_ttl}"
controller_tick: "10s"
target_branch: "${target_branch}"
config_dir: "${config_dir}"
git_repo_url: "${git_repo_url}"
github_webhook_secret: "$WEBHOOK_SECRET"
tls:
  cert_file: /etc/firework/tls/server.crt
  key_file: /etc/firework/tls/server.key
EOF
    ;;
  registry)
    read_secret "${registry_tls_cert_secret}" > /etc/firework/tls/server.crt
    read_secret "${registry_tls_key_secret}" > /etc/firework/tls/server.key
    read_secret "${enrollment_ca_cert_secret}" > /etc/firework/tls/enrollment-ca.crt
    read_secret "${enrollment_ca_key_secret}" > /etc/firework/tls/enrollment-ca.key
    BOOTSTRAP_TOKEN=$(read_secret "${bootstrap_token_secret}")
    cat > /etc/firework/controlplane.yaml <<EOF
role: registry
registry_listen_addr: ":9443"
state:
  backend: gcs
  prefix: "${state_prefix}"
  gcs:
    bucket: "${state_bucket}"
    project: "$PROJECT"
leader_lease_ttl: "30s"
leader_renew_interval: "10s"
node_stale_ttl: "${node_stale_ttl}"
controller_tick: "10s"
tls:
  cert_file: /etc/firework/tls/server.crt
  key_file: /etc/firework/tls/server.key
  client_ca_file: /etc/firework/tls/enrollment-ca.crt
enrollment:
  ca_file: /etc/firework/tls/enrollment-ca.crt
  ca_key_file: /etc/firework/tls/enrollment-ca.key
  node_cert_ttl: "24h"
  bootstrap_tokens:
    - token: "$BOOTSTRAP_TOKEN"
EOF
    ;;
  controller)
    cat > /etc/firework/controlplane.yaml <<EOF
role: controller
state:
  backend: gcs
  prefix: "${state_prefix}"
  gcs:
    bucket: "${state_bucket}"
    project: "$PROJECT"
leader_lease_ttl: "30s"
leader_renew_interval: "10s"
node_stale_ttl: "${node_stale_ttl}"
controller_tick: "10s"
EOF
    ;;
esac

chmod 0600 /etc/firework/controlplane.yaml /etc/firework/tls/* 2>/dev/null || true

cat > /etc/systemd/system/firework-controlplane.service <<'EOF'
[Unit]
Description=Firework control plane
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/firework-controlplane --config /etc/firework/controlplane.yaml
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now firework-controlplane
