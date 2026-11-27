#!/bin/bash
set -euo pipefail
echo "==> Installing Firecracker ${FIRECRACKER_VERSION}"

ARCH="$(uname -m)"
TARBALL="firecracker-v${FIRECRACKER_VERSION}-${ARCH}.tgz"
URL="https://github.com/firecracker-microvm/firecracker/releases/download/v${FIRECRACKER_VERSION}/${TARBALL}"

download_dir=$(mktemp -d)
trap 'rm -r -- "$download_dir"' EXIT
curl -fsSL "${URL}" -o "${download_dir}/${TARBALL}"
tar -xzf "${download_dir}/${TARBALL}" -C "${download_dir}"

RELEASE_DIR="${download_dir}/release-v${FIRECRACKER_VERSION}-${ARCH}"

# Install firecracker binary.
sudo install -m 0755 "${RELEASE_DIR}/firecracker-v${FIRECRACKER_VERSION}-${ARCH}" /usr/bin/firecracker

# Install jailer binary (optional, useful for sandboxing VMs).
if [ -f "${RELEASE_DIR}/jailer-v${FIRECRACKER_VERSION}-${ARCH}" ]; then
  sudo install -m 0755 "${RELEASE_DIR}/jailer-v${FIRECRACKER_VERSION}-${ARCH}" /usr/bin/jailer
fi

# Verify.
echo "Firecracker installed:"
firecracker --version

echo "==> Firecracker installation complete"
