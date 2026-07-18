#!/bin/bash
# shellcheck disable=SC2154 # Terraform template variables are resolved before execution.
set -euo pipefail
umask 077

PROJECT="${gcp_project}"
INSTANCE_NAME=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/name")
PRIMARY_INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -1)
LOCAL_STORAGE_ENABLED="${enable_local_storage}"
LOCAL_STORAGE_CAPACITY="${local_storage_capacity}"
SHARED_STORAGE_ENABLED="${enable_shared_storage}"
SHARED_STORAGE_BACKEND_ID="${shared_storage_backend_id}"
SHARED_STORAGE_CAPACITY="${shared_storage_capacity}"
FILESTORE_IP="${filestore_ip}"
FILESTORE_SHARE="${filestore_share}"

read_secret() {
  gcloud secrets versions access latest --project="$PROJECT" --secret="$1"
}

mkdir -p /etc/firework/pki /var/lib/images /var/lib/firework /etc/traefik/dynamic

if [ "$LOCAL_STORAGE_ENABLED" = "true" ]; then
  LOCAL_STORAGE_DEVICE="/dev/disk/by-id/google-firework-volumes"
  for _attempt in $(seq 1 30); do
    [ -b "$LOCAL_STORAGE_DEVICE" ] && break
    sleep 2
  done
  if [ ! -b "$LOCAL_STORAGE_DEVICE" ]; then
    echo "ERROR: stateful local storage device firework-volumes was not found"
    exit 1
  fi
  _filesystem=$(blkid -o value -s TYPE "$LOCAL_STORAGE_DEVICE" 2>/dev/null || true)
  if [ -z "$_filesystem" ]; then
    if wipefs -n "$LOCAL_STORAGE_DEVICE" | grep -q .; then
      echo "ERROR: local storage device has an unexpected filesystem signature"
      exit 1
    fi
    mkfs.ext4 -F -m 0 -L firework-volumes "$LOCAL_STORAGE_DEVICE"
  elif [ "$_filesystem" != "ext4" ]; then
    echo "ERROR: local storage device filesystem is $_filesystem, expected ext4"
    exit 1
  fi
  LOCAL_STORAGE_UUID=$(blkid -o value -s UUID "$LOCAL_STORAGE_DEVICE")
  install -d -m 0750 /var/lib/firework/volumes
  grep -q "UUID=$LOCAL_STORAGE_UUID " /etc/fstab || \
    echo "UUID=$LOCAL_STORAGE_UUID /var/lib/firework/volumes ext4 defaults,nofail,x-systemd.device-timeout=2min 0 2" >> /etc/fstab
  mountpoint -q /var/lib/firework/volumes || mount /var/lib/firework/volumes
fi

if [ "$SHARED_STORAGE_ENABLED" = "true" ]; then
  install -d -m 0750 /mnt/firework-shared
  grep -q "^$FILESTORE_IP:/$FILESTORE_SHARE /mnt/firework-shared " /etc/fstab || \
    echo "$FILESTORE_IP:/$FILESTORE_SHARE /mnt/firework-shared nfs4 rw,_netdev,nofail,vers=4.1,sec=sys 0 0" >> /etc/fstab
  for _attempt in $(seq 1 30); do
    mountpoint -q /mnt/firework-shared || mount /mnt/firework-shared || true
    mountpoint -q /mnt/firework-shared && break
    sleep 5
  done
  if ! mountpoint -q /mnt/firework-shared; then
    echo "ERROR: Filestore did not mount at /mnt/firework-shared"
    exit 1
  fi
  _marker=/mnt/firework-shared/.firework-backend-id
  if [ -e "$_marker" ] && [ "$(tr -d '\r\n' < "$_marker")" != "$SHARED_STORAGE_BACKEND_ID" ]; then
    echo "ERROR: shared backend identity marker does not match"
    exit 1
  fi
  if [ ! -e "$_marker" ]; then
    printf '%s\n' "$SHARED_STORAGE_BACKEND_ID" > "$_marker.tmp.$INSTANCE_NAME"
    mv -n "$_marker.tmp.$INSTANCE_NAME" "$_marker" || true
    rm -f "$_marker.tmp.$INSTANCE_NAME"
  fi
  if [ "$(tr -d '\r\n' < "$_marker")" != "$SHARED_STORAGE_BACKEND_ID" ]; then
    echo "ERROR: shared backend identity marker changed concurrently"
    exit 1
  fi
fi

mkdir -p /etc/systemd/system/firework-agent.service.d
if [ "$LOCAL_STORAGE_ENABLED" = "true" ] || [ "$SHARED_STORAGE_ENABLED" = "true" ]; then
  cat >/etc/systemd/system/firework-agent.service.d/20-storage.conf <<'EOF'
[Unit]
RequiresMountsFor=/var/lib/firework/volumes /mnt/firework-shared
After=remote-fs.target local-fs.target
EOF
  if [ "$LOCAL_STORAGE_ENABLED" != "true" ]; then
    sed -i 's# /var/lib/firework/volumes##' /etc/systemd/system/firework-agent.service.d/20-storage.conf
  fi
  if [ "$SHARED_STORAGE_ENABLED" != "true" ]; then
    sed -i 's# /mnt/firework-shared##' /etc/systemd/system/firework-agent.service.d/20-storage.conf
  fi
  systemctl daemon-reload
fi
read_secret "${registry_ca_secret}" > /etc/firework/pki/node-ca.crt
REGISTRY_BOOTSTRAP_TOKEN=$(read_secret "${registry_bootstrap_secret}")

gcloud storage cp --no-clobber "gs://${gcs_images_bucket}/*.ext4" /var/lib/images/

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
ingress_domain: "${ingress_domain}"
registry_url: "${registry_url}"
registry_server_name: "${registry_server_name}"
registry_cert_file: "/etc/firework/pki/node.crt"
registry_key_file: "/etc/firework/pki/node.key"
registry_ca_file: "/etc/firework/pki/node-ca.crt"
registry_bootstrap_token: "$REGISTRY_BOOTSTRAP_TOKEN"
EOF

if [ "$LOCAL_STORAGE_ENABLED" = "true" ] || [ "$SHARED_STORAGE_ENABLED" = "true" ]; then
  cat >> /etc/firework/agent.yaml <<'STORAGEHEADER'
storage:
STORAGEHEADER
  if [ "$LOCAL_STORAGE_ENABLED" = "true" ]; then
    cat >> /etc/firework/agent.yaml <<LOCALSTORAGECFG
  local:
    path: "/var/lib/firework/volumes"
    capacity: "$LOCAL_STORAGE_CAPACITY"
LOCALSTORAGECFG
  fi
  if [ "$SHARED_STORAGE_ENABLED" = "true" ]; then
    cat >> /etc/firework/agent.yaml <<SHAREDSTORAGECFG
  shared:
    backend_id: "$SHARED_STORAGE_BACKEND_ID"
    path: "/mnt/firework-shared"
    capacity: "$SHARED_STORAGE_CAPACITY"
SHAREDSTORAGECFG
  fi
fi

chmod 0600 /etc/firework/agent.yaml /etc/firework/pki/node-ca.crt
systemctl restart traefik
systemctl restart firework-agent
