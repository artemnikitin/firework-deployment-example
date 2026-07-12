#!/bin/bash
# Install the architecture-matched Traefik reverse proxy.
set -euo pipefail

TRAEFIK_VERSION="${TRAEFIK_VERSION:-3.3.4}"
case "$(uname -m)" in
  aarch64) ARCH="arm64" ;;
  x86_64) ARCH="amd64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

echo "==> Downloading Traefik v${TRAEFIK_VERSION} (${ARCH})"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL \
  "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_${ARCH}.tar.gz" \
  -o "$TMPDIR/traefik.tar.gz"

tar -xzf "$TMPDIR/traefik.tar.gz" -C "$TMPDIR" traefik

sudo install -m 0755 "$TMPDIR/traefik" /usr/bin/traefik

echo "==> Traefik installed: $(traefik version 2>&1 | head -1)"
