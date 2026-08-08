#!/bin/bash
# shellcheck disable=SC2154
# Note: Variables like ${s3_images_bucket}, ${s3_region}, etc. are Terraform
# template interpolations — they are substituted before the script runs.
set -euo pipefail

# The AMI already has Firecracker, firework-agent, Traefik, kernel, and the
# systemd services baked in (built by Packer). This script:
#   1. Gets the instance ID from EC2 metadata
#   2. Downloads rootfs images from S3
#   3. Writes the node-specific agent config (with instance ID as node name)
#   4. Bootstraps node certificates with the registry bootstrap token
#   5. Configures and starts the CloudWatch Agent (logs + Prometheus metrics)
#   6. Starts Traefik and the firework-agent

IMAGES_DIR="/var/lib/images"
S3_IMAGES_BUCKET="${s3_images_bucket}"
S3_REGION="${s3_region}"
S3_CONFIGS_BUCKET="${s3_configs_bucket}"
S3_CONFIGS_PREFIX="${s3_configs_prefix}"
REGISTRY_URL="${registry_url}"
REGISTRY_SERVER_NAME="${registry_server_name}"
REGISTRY_CLIENT_CA_SECRET_ARN="${registry_client_ca_secret_arn}"
REGISTRY_BOOTSTRAP_TOKEN_SECRET_ARN="${registry_bootstrap_token_secret_arn}"
VM_SUBNET="${vm_subnet}"
VM_GATEWAY="${vm_gateway}"
CW_AGENT_LOG_GROUP_NAME="${cw_agent_log_group_name}"
CW_FIRECRACKER_LOG_GROUP="${cw_firecracker_log_group}"
CW_METRIC_NAMESPACE="${cw_metric_namespace}"
TRAEFIK_CONFIG_DIR="${traefik_config_dir}"
INGRESS_DOMAIN="${ingress_domain}"
LOCAL_STORAGE_ENABLED="${enable_local_storage}"
LOCAL_STORAGE_CAPACITY="${local_storage_capacity}"
SHARED_STORAGE_ENABLED="${enable_shared_storage}"
SHARED_STORAGE_BACKEND_ID="${shared_storage_backend_id}"
SHARED_STORAGE_CAPACITY="${shared_storage_capacity}"
EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
EFS_ACCESS_POINT_ID="${efs_access_point_id}"
REGISTRY_CA_FILE="/etc/firework/pki/node-ca.crt"
REGISTRY_CERT_FILE="/etc/firework/pki/node.crt"
REGISTRY_KEY_FILE="/etc/firework/pki/node.key"
REGISTRY_BOOTSTRAP_TOKEN=""

mkdir -p "$IMAGES_DIR" /var/log

# Cloud-init runs as soon as the instance's primary interface is configured,
# but the subnet's NAT gateway and route may still be converging. Treat every
# cloud/network call as retryable so one early timeout cannot permanently abort
# this one-shot bootstrap under `set -euo pipefail`.
retry() {
  local _label="$1"
  local _attempts="$2"
  local _delay="$3"
  shift 3

  local _attempt
  for ((_attempt = 1; _attempt <= _attempts; _attempt++)); do
    if "$@"; then
      return 0
    fi
    if [ "$_attempt" -eq "$_attempts" ]; then
      break
    fi
    echo "==> $_label attempt $_attempt failed; retrying in $${_delay}s..." >&2
    sleep "$_delay"
    if [ "$_delay" -lt 30 ]; then
      _delay=$((_delay * 2))
      [ "$_delay" -gt 30 ] && _delay=30
    fi
  done
  echo "ERROR: $_label failed after $_attempts attempts" >&2
  return 1
}

wait_for_aws_network() {
  # Any HTTP response proves DNS, routing, NAT/VPC endpoint, and TLS are
  # usable. Do not use --fail: the endpoint may legitimately return 4xx.
  curl -sS --connect-timeout 5 --max-time 10 -o /dev/null \
    "https://ec2.$${S3_REGION}.amazonaws.com"
}

# 20 attempts with capped exponential backoff sleep for about 8.5 minutes
# (plus probe time), covering NAT gateway provisioning and route propagation
# without relying on a cloud-init retry that does not exist for scripts-user.
retry "AWS network readiness" 20 5 wait_for_aws_network

# --- 0. Get instance ID from IMDS (IMDSv2 required) ---
get_imds_token() {
  curl -sS --fail --connect-timeout 2 --max-time 5 -X PUT \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60"
}

get_instance_id() {
  curl -sS --fail --connect-timeout 2 --max-time 5 \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/instance-id"
}

TOKEN=$(retry "IMDSv2 token" 10 2 get_imds_token)
INSTANCE_ID=$(retry "instance ID metadata" 10 2 get_instance_id)
echo "==> Instance ID: $INSTANCE_ID"

# --- 0.0 Prepare operator-provided persistent storage pools ---
if [ "$LOCAL_STORAGE_ENABLED" = "true" ]; then
  LOCAL_STORAGE_DEVICE=""
  for _attempt in $(seq 1 30); do
    for _device in /dev/nvme*n1 /dev/xvdf /dev/sdf; do
      [ -b "$_device" ] || continue
      if command -v ebsnvme-id >/dev/null 2>&1; then
        _mapping=$(ebsnvme-id -u "$_device" 2>/dev/null || true)
        # amazon-ec2-utils returns the normalized mapping name without the
        # /dev/ prefix (for example "sdf"). Accept either representation so
        # Nitro NVMe devices resolve to the launch-template mapping reliably.
        _mapping=$(basename "$_mapping")
        if [ "$_mapping" = "sdf" ]; then
          LOCAL_STORAGE_DEVICE="$_device"
          break
        fi
      elif [ "$_device" = "/dev/xvdf" ] || [ "$_device" = "/dev/sdf" ]; then
        LOCAL_STORAGE_DEVICE="$_device"
        break
      fi
    done
    [ -n "$LOCAL_STORAGE_DEVICE" ] && break
    sleep 2
  done
  if [ -z "$LOCAL_STORAGE_DEVICE" ]; then
    echo "ERROR: retained local storage device /dev/sdf was not found"
    exit 1
  fi

  find_local_storage_volume() {
    local _volume_id
    _volume_id=$(aws ec2 describe-volumes \
      --region "$S3_REGION" \
      --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" "Name=attachment.device,Values=/dev/sdf" \
      --query 'Volumes[0].VolumeId' --output text 2>/dev/null || true)
    if [ -n "$_volume_id" ] && [ "$_volume_id" != "None" ]; then
      printf '%s\n' "$_volume_id"
      return 0
    fi
    return 1
  }

  LOCAL_STORAGE_VOLUME_ID=$(retry "find retained local storage volume" 20 5 find_local_storage_volume)
  retry "tag retained local storage volume" 20 5 \
    aws ec2 create-tags --region "$S3_REGION" --resources "$LOCAL_STORAGE_VOLUME_ID" \
      --tags "Key=FireworkNodeID,Value=$INSTANCE_ID"

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
  EFS_OPTIONS="_netdev,tls,nofail,x-systemd.automount"
  if [ -n "$EFS_ACCESS_POINT_ID" ]; then
    EFS_OPTIONS="$EFS_OPTIONS,accesspoint=$EFS_ACCESS_POINT_ID"
  fi
  grep -q "^$EFS_FILE_SYSTEM_ID:/ /mnt/firework-shared " /etc/fstab || \
    echo "$EFS_FILE_SYSTEM_ID:/ /mnt/firework-shared efs $EFS_OPTIONS 0 0" >> /etc/fstab
  for _attempt in $(seq 1 30); do
    mountpoint -q /mnt/firework-shared || mount /mnt/firework-shared || true
    mountpoint -q /mnt/firework-shared && break
    sleep 5
  done
  if ! mountpoint -q /mnt/firework-shared; then
    echo "ERROR: EFS did not mount at /mnt/firework-shared"
    exit 1
  fi
  _marker=/mnt/firework-shared/.firework-backend-id
  if [ -e "$_marker" ] && [ "$(tr -d '\r\n' < "$_marker")" != "$SHARED_STORAGE_BACKEND_ID" ]; then
    echo "ERROR: shared backend identity marker does not match"
    exit 1
  fi
  if [ ! -e "$_marker" ]; then
    printf '%s\n' "$SHARED_STORAGE_BACKEND_ID" > "$_marker.tmp.$INSTANCE_ID"
    mv -n "$_marker.tmp.$INSTANCE_ID" "$_marker" || true
    rm -f "$_marker.tmp.$INSTANCE_ID"
  fi
  if [ "$(tr -d '\r\n' < "$_marker")" != "$SHARED_STORAGE_BACKEND_ID" ]; then
    echo "ERROR: shared backend identity marker changed concurrently"
    exit 1
  fi
fi

# Disable source/dest check so the host can route east-west VM traffic across
# nodes. This cannot be set in the launch template (provider limitation), so
# we apply it here via the instance's own IAM role.
retry "disable source/dest check" 20 5 \
  aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --no-source-dest-check \
    --region "$S3_REGION"
echo "==> Source/dest check disabled"

# --- 0.1 Ensure SSM agent is available/running (for private-node access) ---
if ! rpm -q amazon-ssm-agent >/dev/null 2>&1; then
  echo "==> amazon-ssm-agent not found in AMI, attempting install"
  dnf install -y amazon-ssm-agent || true
fi
systemctl enable --now amazon-ssm-agent || true

# --- 0.2 Ensure CloudWatch Agent is available ---
if ! rpm -q amazon-cloudwatch-agent >/dev/null 2>&1; then
  echo "==> amazon-cloudwatch-agent not found in AMI, attempting install"
  dnf install -y amazon-cloudwatch-agent || true
fi

# --- 0.3 Configure firework-agent logging to file ---
touch /var/log/firework-agent.log
chmod 0644 /var/log/firework-agent.log
mkdir -p /etc/systemd/system/firework-agent.service.d
cat >/etc/systemd/system/firework-agent.service.d/10-file-logging.conf <<'EOF'
[Service]
StandardOutput=append:/var/log/firework-agent.log
StandardError=append:/var/log/firework-agent.log
EOF
systemctl daemon-reload

if [ "$LOCAL_STORAGE_ENABLED" = "true" ] || [ "$SHARED_STORAGE_ENABLED" = "true" ]; then
  cat >/etc/systemd/system/firework-agent.service.d/20-storage.conf <<'EOF'
[Unit]
RequiresMountsFor=/var/lib/firework/volumes /mnt/firework-shared
After=remote-fs.target local-fs.target
EOF
  # Remove disabled paths so RequiresMountsFor does not create accidental
  # dependencies on directories that are intentionally unused.
  if [ "$LOCAL_STORAGE_ENABLED" != "true" ]; then
    sed -i 's# /var/lib/firework/volumes##' /etc/systemd/system/firework-agent.service.d/20-storage.conf
  fi
  if [ "$SHARED_STORAGE_ENABLED" != "true" ]; then
    sed -i 's# /mnt/firework-shared##' /etc/systemd/system/firework-agent.service.d/20-storage.conf
  fi
  systemctl daemon-reload
fi

# --- 0.4 Write Prometheus scrape config for the firework-agent metrics endpoint ---
# The CW agent will scrape this and publish firework_node_* metrics to CloudWatch
# with the 'node' dimension set to the instance ID (used by the controller service).
mkdir -p /etc/amazon-cloudwatch-agent
cat >/etc/amazon-cloudwatch-agent/prometheus.yaml <<PROMCFG
global:
  scrape_interval: 60s
scrape_configs:
  - job_name: firework-node
    static_configs:
      - targets: ["localhost:8081"]
        labels:
          node: "$INSTANCE_ID"
PROMCFG

# --- 0.5 Configure/start CloudWatch Agent (logs + Prometheus metrics) ---
cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWAGENTCFG
{
  "logs": {
    "force_flush_interval": 15,
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/firework-agent.log",
            "log_group_name": "$CW_AGENT_LOG_GROUP_NAME",
            "log_stream_name": "{instance_id}/firework-agent"
          },
          {
            "file_path": "/var/lib/firework/vms/*/firecracker.log",
            "log_group_name": "$CW_FIRECRACKER_LOG_GROUP",
            "log_stream_name": "{instance_id}/firecracker"
          }
        ]
      }
    },
    "metrics_collected": {
      "prometheus": {
        "log_group_name": "${cw_prometheus_log_group}",
        "prometheus_config_path": "/etc/amazon-cloudwatch-agent/prometheus.yaml",
        "emf_processor": {
          "metric_declaration_dedup": true,
          "metric_namespace": "$CW_METRIC_NAMESPACE",
          "metric_declaration": [
            {
              "source_labels": ["node"],
              "label_matcher": ".+",
              "dimensions": [["node"]],
              "metric_selectors": ["^firework_node_"]
            }
          ]
        }
      }
    }
  }
}
CWAGENTCFG

if [ -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s || true
fi

# --- 1. Download rootfs images from S3 ---
echo "==> Downloading rootfs images from s3://$S3_IMAGES_BUCKET/"
retry "download rootfs images" 20 5 \
  aws s3 sync "s3://$S3_IMAGES_BUCKET/" "$IMAGES_DIR/" \
    --region "$S3_REGION" \
    --exclude "*" --include "*.ext4"
echo "==> Images downloaded"

# --- 2. Write agent config ---
# Detect the primary network interface for masquerade (agent needs this).
PRIMARY_IF=$(ip -o route get 1.1.1.1 | awk '{print $5}')
echo "==> Detected primary interface: $PRIMARY_IF"

if [ -n "$REGISTRY_URL" ]; then
  echo "==> Preparing registry trust material"

  mkdir -p /etc/firework/pki

  if [ -z "$REGISTRY_CLIENT_CA_SECRET_ARN" ]; then
    echo "ERROR: registry_url is set but no CA secret ARN is configured"
    echo "       Set registry_client_ca_secret_arn in the control-plane outputs."
    exit 1
  fi

  retry "download registry CA secret" 20 5 \
    aws secretsmanager get-secret-value \
      --secret-id "$REGISTRY_CLIENT_CA_SECRET_ARN" \
      --region "$S3_REGION" \
      --query SecretString \
      --output text > "$REGISTRY_CA_FILE"
  chmod 0644 "$REGISTRY_CA_FILE"

  if [ -n "$REGISTRY_BOOTSTRAP_TOKEN_SECRET_ARN" ]; then
    REGISTRY_BOOTSTRAP_TOKEN=$(retry "download registry bootstrap token" 20 5 \
      aws secretsmanager get-secret-value \
        --secret-id "$REGISTRY_BOOTSTRAP_TOKEN_SECRET_ARN" \
        --region "$S3_REGION" \
        --query SecretString \
        --output text)
  else
    echo "ERROR: registry_url is set but registry_bootstrap_token_secret_arn is not configured"
    exit 1
  fi
fi

echo "==> Writing agent config"
cat > /etc/firework/agent.yaml <<AGENTCFG
node_names:
  - "$INSTANCE_ID"
store_type: "s3"
s3_bucket: "$S3_CONFIGS_BUCKET"
s3_prefix: "$S3_CONFIGS_PREFIX"
s3_region: "$S3_REGION"
s3_images_bucket: "$S3_IMAGES_BUCKET"
images_dir: "$IMAGES_DIR"
poll_interval: "30s"
firecracker_bin: "/usr/bin/firecracker"
state_dir: "/var/lib/firework"
log_level: "info"
api_listen_addr: ":8081"
enable_health_checks: true
enable_network_setup: true
vm_bridge: "br0"
vm_subnet: "$VM_SUBNET"
vm_gateway: "$VM_GATEWAY"
out_interface: "$PRIMARY_IF"
traefik_config_dir: "$TRAEFIK_CONFIG_DIR"
ingress_domain: "$INGRESS_DOMAIN"
AGENTCFG

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
SHAREDSTORAGECFG
    if [ -n "$SHARED_STORAGE_CAPACITY" ]; then
      printf '    capacity: "%s"\n' "$SHARED_STORAGE_CAPACITY" >> /etc/firework/agent.yaml
    fi
  fi
fi

if [ -n "$REGISTRY_URL" ]; then
  cat >> /etc/firework/agent.yaml <<REGISTRYCFG
registry_url: "$REGISTRY_URL"
registry_server_name: "$REGISTRY_SERVER_NAME"
registry_cert_file: "$REGISTRY_CERT_FILE"
registry_key_file: "$REGISTRY_KEY_FILE"
registry_ca_file: "$REGISTRY_CA_FILE"
REGISTRYCFG

  if [ -n "$REGISTRY_BOOTSTRAP_TOKEN" ]; then
    cat >> /etc/firework/agent.yaml <<REGISTRYTOKENCFG
registry_bootstrap_token: "$REGISTRY_BOOTSTRAP_TOKEN"
REGISTRYTOKENCFG
  fi
fi

# --- 3. Start Traefik ---
echo "==> Starting Traefik"
systemctl restart traefik

# --- 4. Start the agent ---
echo "==> Starting firework-agent"
systemctl restart firework-agent

echo "==> User-data complete"
