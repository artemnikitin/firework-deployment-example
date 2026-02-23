#!/bin/bash
set -euo pipefail
echo "==> Installing Firecracker ${FIRECRACKER_VERSION}"

ARCH="aarch64"
TARBALL="firecracker-v${FIRECRACKER_VERSION}-${ARCH}.tgz"
URL="https://github.com/firecracker-microvm/firecracker/releases/download/v${FIRECRACKER_VERSION}/${TARBALL}"

cd /tmp
curl -sL "${URL}" -o "${TARBALL}"
tar -xzf "${TARBALL}"

RELEASE_DIR="release-v${FIRECRACKER_VERSION}-${ARCH}"

# Install firecracker binary.
sudo mv "${RELEASE_DIR}/firecracker-v${FIRECRACKER_VERSION}-${ARCH}" /usr/bin/firecracker
sudo chmod +x /usr/bin/firecracker

# Install jailer binary (optional, useful for sandboxing VMs).
if [ -f "${RELEASE_DIR}/jailer-v${FIRECRACKER_VERSION}-${ARCH}" ]; then
  sudo mv "${RELEASE_DIR}/jailer-v${FIRECRACKER_VERSION}-${ARCH}" /usr/bin/jailer
  sudo chmod +x /usr/bin/jailer
fi

# Clean up.
rm -rf "${RELEASE_DIR}" "${TARBALL}"

# Verify.
echo "Firecracker installed:"
firecracker --version

echo "==> Firecracker installation complete"
