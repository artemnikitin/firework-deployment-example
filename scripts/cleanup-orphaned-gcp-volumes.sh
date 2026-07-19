#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  cleanup-orphaned-gcp-volumes.sh --project <gcp-project> --deployment-name <name> [--delete]

Lists unattached Firework local-storage disks created by the regional managed
instance group. The current instance-template contract names those data disks
<deployment-name>-node-<instance-suffix>-1; boot disks do not match this
suffix. Without --delete it is a dry run. --delete permanently removes each
listed disk. Restore any required application data from backups first.
EOF
}

project=""
deployment_name=""
delete=false

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

if [[ -z "$project" || -z "$deployment_name" ]]; then
  usage >&2
  exit 2
fi

command -v gcloud >/dev/null 2>&1 || {
  echo "ERROR: gcloud CLI is required" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required" >&2
  exit 1
}

candidates=$(gcloud compute disks list --project "$project" --format=json | jq -r --arg prefix "${deployment_name}-node-" '
  .[]
  | select(((.users // []) | length) == 0)
  | select((.name | startswith($prefix)) and (.name | endswith("-1")))
  | select((.type | endswith("hyperdisk-balanced")) or (.type | endswith("pd-balanced")))
  | [.name, (.zone | split("/")[-1]), .sizeGb, .type, .creationTimestamp]
  | @tsv
')

if [[ -z "$candidates" ]]; then
  echo "No unattached retained Firework disks found for deployment $deployment_name in project $project."
  exit 0
fi

printf '%s\n' "Matched unattached retained Firework disks:"
printf 'NAME\tZONE\tSIZE_GIB\tTYPE\tCREATED\n'
printf '%s\n' "$candidates"

if [[ "$delete" != true ]]; then
  echo "Dry run only. Re-run with --delete to permanently remove these disks."
  exit 0
fi

while IFS=$'\t' read -r name zone _size _type _created; do
  [[ -z "$name" || -z "$zone" ]] && continue
  echo "Deleting $name in $zone"
  gcloud compute disks delete "$name" --zone "$zone" --project "$project" --quiet
done <<< "$candidates"
