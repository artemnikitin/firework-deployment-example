#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  cleanup-orphaned-aws-volumes.sh --region <aws-region> --project-name <name> [--profile <profile>] [--config-bucket <s3-bucket>] [--config-prefix <prefix>] [--delete]

Lists unattached EBS volumes created for Firework local storage. The script
matches only volumes with all of these properties:
  - state: available (unattached)
  - Retention=manual
  - Name=<project-name>-node-volume

When --config-bucket is supplied, the script also matches retained local-volume
records whose bound EC2 instance no longer exists. Without --delete it is a dry
run. --delete permanently removes each listed volume and record. Restore any
required application data from backups before using it.
EOF
}

region=""
project_name=""
profile=""
config_bucket=""
config_prefix="cp/v1/"
delete=false

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
    --config-bucket)
      config_bucket="${2:-}"
      shift 2
      ;;
    --config-prefix)
      config_prefix="${2:-}"
      shift 2
      ;;
    --delete)
      delete=true
      shift
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

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: aws CLI is required" >&2
  exit 1
}

aws_args=(--region "$region")
if [[ -n "$profile" ]]; then
  aws_args+=(--profile "$profile")
fi

volume_ids=()
while IFS= read -r volume_id; do
  [[ -z "$volume_id" || "$volume_id" == "None" ]] && continue
  volume_ids+=("$volume_id")
done < <(
  aws "${aws_args[@]}" ec2 describe-volumes \
    --filters \
      "Name=status,Values=available" \
      "Name=tag:Retention,Values=manual" \
      "Name=tag:Name,Values=${project_name}-node-volume" \
    --query 'Volumes[].VolumeId' \
    --output text | tr '\t' '\n'
)

if ((${#volume_ids[@]} == 0)); then
  echo "No unattached retained Firework volumes found for project $project_name in $region."
else
  echo "Matched unattached retained Firework volumes:"
  # shellcheck disable=SC2016 # AWS CLI JMESPath uses literal backticks.
  aws "${aws_args[@]}" ec2 describe-volumes \
    --volume-ids "${volume_ids[@]}" \
    --query 'Volumes[].{ID:VolumeId,SizeGiB:Size,Created:CreateTime,Node:Tags[?Key==`FireworkNodeID`]|[0].Value}' \
    --output table

  if [[ "$delete" == true ]]; then
    for volume_id in "${volume_ids[@]}"; do
      echo "Deleting $volume_id"
      aws "${aws_args[@]}" ec2 delete-volume --volume-id "$volume_id"
    done
  else
    echo "Dry run only. Re-run with --delete to permanently remove these volumes."
  fi
fi

if [[ -n "$config_bucket" ]]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  record_args=(
    --provider aws
    --bucket "$config_bucket"
    --prefix "$config_prefix"
    --region "$region"
  )
  if [[ -n "$profile" ]]; then
    record_args+=(--profile "$profile")
  fi
  if [[ "$delete" == true ]]; then
    record_args+=(--delete)
  fi
  "$script_dir/cleanup-orphaned-volume-records.sh" "${record_args[@]}"
fi
