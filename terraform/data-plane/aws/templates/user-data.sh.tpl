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
#   4. Optionally bootstraps node certs from step-ca (AWS IID)
#   5. Configures and starts the CloudWatch Agent (logs + Prometheus metrics)
#   6. Starts Traefik and the firework-agent

IMAGES_DIR="/var/lib/images"
S3_IMAGES_BUCKET="${s3_images_bucket}"
S3_REGION="${s3_region}"
S3_CONFIGS_BUCKET="${s3_configs_bucket}"
S3_CONFIGS_PREFIX="${s3_configs_prefix}"
REGISTRY_URL="${registry_url}"
REGISTRY_SERVER_NAME="${registry_server_name}"
STEP_CA_URL="${step_ca_url}"
STEP_CA_ROOT_CA_SECRET_ARN="${step_ca_root_ca_secret_arn}"
STEP_CA_PROVISIONER="${step_ca_provisioner}"
STEP_CA_SUBJECT_SUFFIX="${step_ca_subject_suffix}"
STEP_CA_RENEW_EXPIRES_IN="${step_ca_renew_expires_in}"
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
STEP_BIN=""

mkdir -p "$IMAGES_DIR" /var/log

# --- 0. Get instance ID from IMDS (IMDSv2 required) ---
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")
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

  LOCAL_STORAGE_VOLUME_ID=$(aws ec2 describe-volumes \
    --region "$S3_REGION" \
    --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" "Name=attachment.device,Values=/dev/sdf" \
    --query 'Volumes[0].VolumeId' --output text)
  if [ -z "$LOCAL_STORAGE_VOLUME_ID" ] || [ "$LOCAL_STORAGE_VOLUME_ID" = "None" ]; then
    echo "ERROR: retained local storage volume ID was not found"
    exit 1
  fi
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
# Retry up to 3 times to handle transient credential/API hiccups at boot.
for _attempt in 1 2 3; do
  aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --no-source-dest-check \
    --region "$S3_REGION" && break
  echo "==> source/dest check attempt $_attempt failed, retrying in $${_attempt}0s..."
  sleep $((_attempt * 10))
done
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

install_step_cli() {
  if command -v step >/dev/null 2>&1; then
    STEP_BIN="$(command -v step)"
    return
  fi

  cat >/etc/yum.repos.d/smallstep.repo <<'EOF'
[smallstep]
name=Smallstep
baseurl=https://packages.smallstep.com/stable/fedora/
enabled=1
repo_gpgcheck=0
gpgcheck=1
gpgkey=https://packages.smallstep.com/keys/smallstep-0x889B19391F774443.gpg
EOF

  dnf makecache -y
  dnf install -y step-cli
  STEP_BIN="$(command -v step)"
  if [ -z "$STEP_BIN" ]; then
    echo "ERROR: step CLI install failed"
    exit 1
  fi
}

# --- 1. Download rootfs images from S3 ---
echo "==> Downloading rootfs images from s3://$S3_IMAGES_BUCKET/"
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

  REGISTRY_CA_SECRET_ARN="$REGISTRY_CLIENT_CA_SECRET_ARN"
  if [ -n "$STEP_CA_ROOT_CA_SECRET_ARN" ]; then
    REGISTRY_CA_SECRET_ARN="$STEP_CA_ROOT_CA_SECRET_ARN"
  fi
  if [ -z "$REGISTRY_CA_SECRET_ARN" ]; then
    echo "ERROR: registry_url is set but no CA secret ARN is configured"
    echo "       Set step_ca_root_ca_secret_arn (preferred) or registry_client_ca_secret_arn (legacy)."
    exit 1
  fi

  aws secretsmanager get-secret-value \
    --secret-id "$REGISTRY_CA_SECRET_ARN" \
    --region "$S3_REGION" \
    --query SecretString \
    --output text > "$REGISTRY_CA_FILE"
  chmod 0644 "$REGISTRY_CA_FILE"

  if [ -n "$STEP_CA_URL" ]; then
    echo "==> Bootstrapping node certificate via step-ca AWS IID provisioner"
    install_step_cli

    STEP_CA_ROOT_FINGERPRINT=$("$STEP_BIN" certificate fingerprint "$REGISTRY_CA_FILE")
    "$STEP_BIN" ca bootstrap \
      --ca-url "$STEP_CA_URL" \
      --fingerprint "$STEP_CA_ROOT_FINGERPRINT" \
      --install \
      --force

    STEP_NODE_SUBJECT="$INSTANCE_ID$STEP_CA_SUBJECT_SUFFIX"
    "$STEP_BIN" ca certificate "$STEP_NODE_SUBJECT" \
      "$REGISTRY_CERT_FILE" "$REGISTRY_KEY_FILE" \
      --provisioner "$STEP_CA_PROVISIONER" \
      --ca-url "$STEP_CA_URL" \
      --root "$REGISTRY_CA_FILE" \
      --force
    chmod 0600 "$REGISTRY_KEY_FILE"

    cat >/etc/systemd/system/firework-step-renew.service <<EOF
[Unit]
Description=Renew Firework node certificate via step-ca
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$STEP_BIN ca renew --daemon --expires-in $STEP_CA_RENEW_EXPIRES_IN --force --ca-url $STEP_CA_URL --root $REGISTRY_CA_FILE --exec "systemctl restart firework-agent" $REGISTRY_CERT_FILE $REGISTRY_KEY_FILE
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now firework-step-renew.service
  elif [ -n "$REGISTRY_BOOTSTRAP_TOKEN_SECRET_ARN" ]; then
    REGISTRY_BOOTSTRAP_TOKEN=$(aws secretsmanager get-secret-value \
      --secret-id "$REGISTRY_BOOTSTRAP_TOKEN_SECRET_ARN" \
      --region "$S3_REGION" \
      --query SecretString \
      --output text)
  else
    echo "ERROR: registry_url is set but neither step_ca_url nor registry_bootstrap_token_secret_arn is configured"
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
