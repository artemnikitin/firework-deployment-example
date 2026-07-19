#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  destroy-gcp-data-plane.sh --project <gcp-project> --deployment-name <name> [-- <terraform destroy args>]

Runs the GCP data-plane Terraform destroy. Only after it succeeds, permanently
deletes matching unattached retained Firework local-storage disks.

Example:
  destroy-gcp-data-plane.sh --project example-project --deployment-name firework -- -auto-approve
EOF
}

project=""
deployment_name=""
terraform_args=()

while (($#)); do
  case "$1" in
    --project)
      project="${2:-}"
      shift 2
      ;;
    --deployment-name)
      deployment_name="${2:-}"
      shift 2
      ;;
    --)
      shift
      terraform_args=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$project" || -z "$deployment_name" ]]; then
  usage >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
(
  cd "$script_dir/../terraform/data-plane/gcp"
  terraform destroy "${terraform_args[@]}"
)

"$script_dir/cleanup-orphaned-gcp-volumes.sh" \
  --project "$project" \
  --deployment-name "$deployment_name" \
  --delete
