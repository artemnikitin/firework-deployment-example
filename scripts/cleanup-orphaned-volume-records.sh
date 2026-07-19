#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  cleanup-orphaned-volume-records.sh --provider aws --bucket <s3-bucket> --prefix <state-prefix> --region <aws-region> [--profile <profile>] [--delete]
  cleanup-orphaned-volume-records.sh --provider gcp --bucket <gcs-bucket> --prefix <state-prefix> --project <gcp-project> [--delete]

Lists retained local-volume records whose bound node no longer exists. Active
or stopped nodes are never selected. Without --delete this is a dry run.
EOF
}

provider=""
bucket=""
prefix="cp/v1/"
region=""
profile=""
project=""
delete=false

while (($#)); do
  case "$1" in
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --bucket)
      bucket="${2:-}"
      shift 2
      ;;
    --prefix)
      prefix="${2:-}"
      shift 2
      ;;
    --region)
      region="${2:-}"
      shift 2
      ;;
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --project)
      project="${2:-}"
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

if [[ -z "$bucket" || ( "$provider" != "aws" && "$provider" != "gcp" ) ]]; then
  usage >&2
  exit 2
fi
if [[ "$provider" == "aws" && -z "$region" ]]; then
  usage >&2
  exit 2
fi
if [[ "$provider" == "gcp" && -z "$project" ]]; then
  usage >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required" >&2
  exit 1
}

prefix="${prefix#/}"
prefix="${prefix%/}"
records_prefix="${prefix:+${prefix}/}volumes/"
orphan_records=()
aws_args=()

record_is_orphaned() {
  local bound_node="$1"
  local state

  if [[ "$provider" == "aws" ]]; then
    [[ "$bound_node" =~ ^i-[0-9a-f]+$ ]] || return 1
    if state=$(aws "${aws_args[@]}" ec2 describe-instances \
      --instance-ids "$bound_node" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text 2>/dev/null); then
      [[ -z "$state" || "$state" == "None" || "$state" == "shutting-down" || "$state" == "terminated" ]]
      return
    fi
    return 0
  fi

  [[ "$bound_node" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ ]] || return 1
  state=$(gcloud compute instances list \
    --project "$project" \
    --filter="name=($bound_node)" \
    --format='value(status)')
  [[ -z "$state" ]]
}

inspect_record() {
  local location="$1"
  local content="$2"
  local type logical_id bound_node

  type=$(jq -r '.type // ""' <<< "$content")
  [[ "$type" == "local" ]] || return 0
  logical_id=$(jq -r '.logical_id // ""' <<< "$content")
  bound_node=$(jq -r '.bound_node // ""' <<< "$content")
  [[ -n "$logical_id" && -n "$bound_node" ]] || {
    echo "WARNING: skipping malformed local-volume record $location" >&2
    return 0
  }
  if record_is_orphaned "$bound_node"; then
    orphan_records+=("${location}"$'\t'"${logical_id}"$'\t'"${bound_node}")
  fi
}

if [[ "$provider" == "aws" ]]; then
  command -v aws >/dev/null 2>&1 || {
    echo "ERROR: aws CLI is required" >&2
    exit 1
  }
  aws_args=(--region "$region")
  if [[ -n "$profile" ]]; then
    aws_args+=(--profile "$profile")
  fi

  while IFS= read -r key; do
    [[ -z "$key" || "$key" == "None" ]] && continue
    content=$(aws "${aws_args[@]}" s3 cp "s3://${bucket}/${key}" - --only-show-errors)
    inspect_record "$key" "$content"
  done < <(
    aws "${aws_args[@]}" s3api list-objects-v2 \
      --bucket "$bucket" \
      --prefix "$records_prefix" \
      --query 'Contents[].Key' \
      --output text | tr '\t' '\n'
  )
else
  command -v gcloud >/dev/null 2>&1 || {
    echo "ERROR: gcloud CLI is required" >&2
    exit 1
  }

  while IFS= read -r uri; do
    [[ -z "$uri" ]] && continue
    content=$(gcloud storage cat "$uri" --project "$project")
    inspect_record "$uri" "$content"
  done < <(gcloud storage ls "gs://${bucket}/${records_prefix}**" --project "$project" 2>/dev/null || true)
fi

if ((${#orphan_records[@]} == 0)); then
  echo "No orphaned retained local-volume records found in ${provider}://${bucket}/${records_prefix}."
  exit 0
fi

echo "Matched orphaned retained local-volume records:"
printf 'LOGICAL_ID\tBOUND_NODE\tOBJECT\n'
for record in "${orphan_records[@]}"; do
  IFS=$'\t' read -r location logical_id bound_node <<< "$record"
  printf '%s\t%s\t%s\n' "$logical_id" "$bound_node" "$location"
done

if [[ "$delete" != true ]]; then
  echo "Dry run only. Re-run with --delete to permanently remove these records."
  exit 0
fi

for record in "${orphan_records[@]}"; do
  IFS=$'\t' read -r location _logical_id _bound_node <<< "$record"
  echo "Deleting volume record $location"
  if [[ "$provider" == "aws" ]]; then
    aws "${aws_args[@]}" s3api delete-object --bucket "$bucket" --key "$location" >/dev/null
  else
    gcloud storage rm "$location" --project "$project"
  fi
done
