#!/bin/bash
set -euo pipefail
echo "==> Downloading Firecracker-compatible kernel"

ARCH="$(uname -m)"
IMAGES_DIR="/var/lib/images"

sudo mkdir -p "$IMAGES_DIR"

# The Firecracker CI kernel family is intentionally independent from the
# Firecracker binary version. New Firecracker releases do not necessarily
# publish a matching kernel prefix in the CI bucket.
CI_VERSION="${FIRECRACKER_KERNEL_VERSION:-1.15}"
CI_VERSION="v${CI_VERSION#v}"

# Discover the latest 5.10.x kernel available for this CI version.
KERNEL_KEY=$(curl -fsSL \
  "https://s3.amazonaws.com/spec.ccfc.min/?prefix=firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-5.10&list-type=2" \
  | grep -oE "firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-5\\.10\\.[0-9]+" \
  | sort -V | tail -1)

if [ -z "${KERNEL_KEY}" ]; then
  echo "ERROR: Could not find a vmlinux-5.10.x kernel for Firecracker ${CI_VERSION} / ${ARCH}"
  exit 1
fi

KERNEL_FILENAME=$(basename "${KERNEL_KEY}")
KERNEL_URL="https://s3.amazonaws.com/spec.ccfc.min/${KERNEL_KEY}"

# Save with the canonical two-part name (e.g. vmlinux-5.10) so the control-plane
# default kernel path (/var/lib/images/vmlinux-5.10) resolves without a symlink.
KERNEL_MAJOR_MINOR=$(echo "${KERNEL_FILENAME}" | grep -oE "vmlinux-[0-9]+\.[0-9]+")
KERNEL_PATH="${IMAGES_DIR}/${KERNEL_MAJOR_MINOR}"

echo "Downloading kernel from: ${KERNEL_URL}"
sudo curl -fsSL "${KERNEL_URL}" -o "${KERNEL_PATH}"
sudo chmod 644 "${KERNEL_PATH}"

# Verify the file was downloaded.
if [ ! -s "${KERNEL_PATH}" ]; then
  echo "WARNING: Kernel download may have failed. File is empty or missing."
  echo "You may need to manually place a kernel at ${KERNEL_PATH}"
else
  echo "Kernel installed: ${KERNEL_PATH} ($(du -h "${KERNEL_PATH}" | cut -f1))"
fi

echo "==> Kernel download complete"
