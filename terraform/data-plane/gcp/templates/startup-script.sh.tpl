#!/bin/bash
# shellcheck disable=SC2154 # Terraform template variables are resolved before execution.
set -euo pipefail
umask 077

PROJECT="${gcp_project}"
INSTANCE_NAME=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/name")
PRIMARY_INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -1)

read_secret() {
  gcloud secrets versions access latest --project="$PROJECT" --secret="$1"
}

mkdir -p /etc/firework/pki /var/lib/images /var/lib/firework /etc/traefik/dynamic
read_secret "${registry_ca_secret}" > /etc/firework/pki/node-ca.crt
REGISTRY_BOOTSTRAP_TOKEN=$(read_secret "${registry_bootstrap_secret}")

gcloud storage rsync --recursive "gs://${gcs_images_bucket}/" /var/lib/images/

cat > /etc/firework/agent.yaml <<EOF
node_id: "$INSTANCE_NAME"
node_names:
  - "$INSTANCE_NAME"
store_type: "gcs"
gcs_bucket: "${gcs_configs_bucket}"
gcs_prefix: "${gcs_configs_prefix}"
gcs_project: "$PROJECT"
gcs_images_bucket: "${gcs_images_bucket}"
images_dir: "/var/lib/images"
poll_interval: "30s"
firecracker_bin: "/usr/bin/firecracker"
state_dir: "/var/lib/firework"
log_level: "info"
api_listen_addr: ":8081"
enable_health_checks: true
enable_network_setup: true
vm_bridge: "br0"
vm_subnet: "${vm_subnet}"
vm_gateway: "${vm_gateway}"
out_interface: "$PRIMARY_INTERFACE"
traefik_config_dir: "/etc/traefik/dynamic"
registry_url: "${registry_url}"
registry_server_name: "${registry_server_name}"
registry_cert_file: "/etc/firework/pki/node.crt"
registry_key_file: "/etc/firework/pki/node.key"
registry_ca_file: "/etc/firework/pki/node-ca.crt"
registry_bootstrap_token: "$REGISTRY_BOOTSTRAP_TOKEN"
EOF

chmod 0600 /etc/firework/agent.yaml /etc/firework/pki/node-ca.crt
systemctl restart traefik
systemctl restart firework-agent
