#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  destroy-aws-data-plane.sh --region <aws-region> --project-name <name> [--profile <profile>] [-- <terraform destroy args>]

Runs the AWS data-plane Terraform destroy. Only after it succeeds, permanently
deletes matching unattached retained Firework local-storage volumes and local
volume records whose bound EC2 instance no longer exists.

Example:
  destroy-aws-data-plane.sh --region us-east-1 --project-name firework-demo -- -auto-approve
EOF
}

region=""
project_name=""
profile=""
terraform_args=()

while (($#)); do
  case "$1" in
    --region)
      region="${2:-}"
      shift 2
      ;;
    --project-name)
      project_name="${2:-}"
      shift 2
      ;;
    --profile)
      profile="${2:-}"
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

if [[ -z "$region" || -z "$project_name" ]]; then
  usage >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -n "$profile" ]]; then
  export AWS_PROFILE="$profile"
fi

if ! config_bucket=$(terraform -chdir="$script_dir/../terraform/data-plane/aws" output -raw configs_bucket_name 2>/dev/null); then
  config_bucket=$(terraform -chdir="$script_dir/../terraform/control-plane/aws" output -raw config_bucket_name)
fi
if ! config_prefix=$(terraform -chdir="$script_dir/../terraform/data-plane/aws" output -raw configs_bucket_prefix 2>/dev/null); then
  config_prefix=$(terraform -chdir="$script_dir/../terraform/control-plane/aws" output -raw config_prefix)
fi

(
  cd "$script_dir/../terraform/data-plane/aws"
  terraform destroy "${terraform_args[@]}"
)

cleanup_args=(
  --region "$region"
  --project-name "$project_name"
  --config-bucket "$config_bucket"
  --config-prefix "$config_prefix"
  --delete
)
if [[ -n "$profile" ]]; then
  cleanup_args+=(--profile "$profile")
fi
"$script_dir/cleanup-orphaned-aws-volumes.sh" "${cleanup_args[@]}"
