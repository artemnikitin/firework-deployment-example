#!/bin/bash
set -euo pipefail
echo "==> Downloading Firecracker-compatible kernel"

ARCH="$(uname -m)"
KERNEL_PATH="/var/lib/images/vmlinux-5.10"
S3_URL="https://s3.amazonaws.com/spec.ccfc.min"
CI_VERSION="v$(echo "${FIRECRACKER_VERSION}" | cut -d. -f1,2)"
KERNEL_SHA256=""

case "${CI_VERSION}" in
  v1.18)
    # Pin a dated CI build. Firework and GitOps still use the 5.10 guest kernel path.
    KERNEL_KEY="firecracker-ci/20261105-6ea6634994fa-0/${ARCH}/vmlinux-5.10.271"
    case "${ARCH}" in
      x86_64) KERNEL_SHA256="38d9d7a4096e95df6d236c6372e5b8f8928892503517cb723187c31cc418bc74" ;;
      aarch64) KERNEL_SHA256="5174656f19dfb09b087e044b1ba149eaac3c83825fcb167179961774e37648c8" ;;
      *) echo "ERROR: Unsupported kernel architecture: ${ARCH}" >&2; exit 1 ;;
    esac
    ;;
  *)
    # Older Firecracker overrides can still use the release-specific CI prefixes.
    KERNEL_PREFIX="firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-5.10"
    KERNEL_LIST="$(curl -fsSL "${S3_URL}/?prefix=${KERNEL_PREFIX}&list-type=2")"
    KERNEL_KEY=$(printf '%s' "${KERNEL_LIST}" \
      | { grep -oE '<Key>[^<]+/vmlinux-5\.10\.[0-9]+</Key>' || true; } \
      | sed -e 's|^<Key>||' -e 's|</Key>$||' \
      | sort -V | tail -1)
    ;;
esac

if [ -z "${KERNEL_KEY}" ]; then
  echo "ERROR: Could not find a vmlinux-5.10.x kernel for Firecracker ${CI_VERSION} / ${ARCH}" >&2
  exit 1
fi

KERNEL_URL="${S3_URL}/${KERNEL_KEY}"
download_file=$(mktemp)
trap 'rm -- "$download_file"' EXIT
echo "Downloading kernel from: ${KERNEL_URL}"
curl -fsSL "${KERNEL_URL}" -o "${download_file}"
if [ ! -s "${download_file}" ]; then
  echo "ERROR: Kernel download is empty: ${KERNEL_URL}" >&2
  exit 1
fi
if [ -n "${KERNEL_SHA256}" ]; then
  printf '%s  %s\n' "${KERNEL_SHA256}" "${download_file}" | sha256sum -c -
fi

sudo install -D -m 0644 "${download_file}" "${KERNEL_PATH}"
echo "Kernel installed: ${KERNEL_PATH}"
