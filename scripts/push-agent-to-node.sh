#!/usr/bin/env bash
set -euo pipefail

# push-agent-to-node.sh
# Deploy a local firework-agent binary to an existing node by copying it
# directly over SCP tunneled via SSM (AWS-StartSSHSession).

INSTANCE_ID=""
AGENT_PATH=""
REGION="${AWS_REGION:-us-east-1}"
SSH_USER="ec2-user"
SSH_KEY=""

usage() {
  cat <<'EOF'
Usage:
  push-agent-to-node.sh --instance-id <id> --agent-path <path> --ssh-key <path> [options]

Required:
  --instance-id <id>   Target EC2 instance ID (must be SSM-managed)
  --agent-path <path>  Local path to firework-agent binary
  --ssh-key <path>     SSH private key for the target instance

Options:
  --region <region>    AWS region (default: AWS_REGION or us-east-1)
  --ssh-user <user>    SSH user (default: ec2-user)
  -h, --help           Show this help

Example:
  ./scripts/push-agent-to-node.sh \
    --instance-id i-0123456789abcdef0 \
    --agent-path ../firework/bin/firework-agent-linux-arm64 \
    --ssh-key ~/.ssh/firework-demo.pem \
    --region us-east-1
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    exit 1
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --instance-id)
      INSTANCE_ID="${2:-}"
      shift 2
      ;;
    --agent-path)
      AGENT_PATH="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2:-}"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd aws
require_cmd ssh
require_cmd scp

if [ -z "${INSTANCE_ID}" ]; then
  echo "ERROR: --instance-id is required" >&2
  usage
  exit 1
fi

if [ -z "${AGENT_PATH}" ]; then
  echo "ERROR: --agent-path is required" >&2
  usage
  exit 1
fi

if [ ! -f "${AGENT_PATH}" ]; then
  echo "ERROR: agent binary not found: ${AGENT_PATH}" >&2
  exit 1
fi

if [ ! -s "${AGENT_PATH}" ]; then
  echo "ERROR: agent binary is empty: ${AGENT_PATH}" >&2
  exit 1
fi

if [ -z "${SSH_KEY}" ]; then
  echo "ERROR: --ssh-key is required" >&2
  usage
  exit 1
fi

if [ ! -f "${SSH_KEY}" ]; then
  echo "ERROR: ssh key not found: ${SSH_KEY}" >&2
  exit 1
fi

PROXY_CMD="sh -c 'aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${REGION}'"
SSH_OPTS=(
  -i "${SSH_KEY}"
  -o "ProxyCommand=${PROXY_CMD}"
  -o "StrictHostKeyChecking=no"
  -o "UserKnownHostsFile=/dev/null"
  -o "IdentitiesOnly=yes"
)

echo "==> Copying agent binary to ${INSTANCE_ID}:/tmp/firework-agent.new"
scp "${SSH_OPTS[@]}" "${AGENT_PATH}" "${SSH_USER}@${INSTANCE_ID}:/tmp/firework-agent.new"

echo "==> Installing binary and restarting service"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${INSTANCE_ID}" \
  "set -euo pipefail; \
   sudo install -m 0755 /tmp/firework-agent.new /usr/bin/firework-agent; \
   rm -f /tmp/firework-agent.new; \
   sudo systemctl restart firework-agent; \
   sudo systemctl is-active firework-agent; \
   sudo /usr/bin/firework-agent --version || true"

echo "==> Agent deploy complete"
