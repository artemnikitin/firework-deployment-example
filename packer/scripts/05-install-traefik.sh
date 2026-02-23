#!/bin/bash
# Install Traefik reverse proxy (arm64 binary).
# Called by Packer during AMI build.
set -euo pipefail

TRAEFIK_VERSION="${TRAEFIK_VERSION:-3.3.4}"
ARCH="arm64"

echo "==> Downloading Traefik v${TRAEFIK_VERSION} (${ARCH})"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL \
  "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_${ARCH}.tar.gz" \
  -o "$TMPDIR/traefik.tar.gz"

tar -xzf "$TMPDIR/traefik.tar.gz" -C "$TMPDIR" traefik

sudo install -m 0755 "$TMPDIR/traefik" /usr/bin/traefik

echo "==> Traefik installed: $(traefik version 2>&1 | head -1)"
