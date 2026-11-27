#!/bin/bash
# Install the architecture-matched Traefik reverse proxy.
set -euo pipefail

TRAEFIK_VERSION="${TRAEFIK_VERSION:-3.8.0}"
case "$(uname -m)" in
  aarch64) ARCH="arm64" ;;
  x86_64) ARCH="amd64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

echo "==> Downloading Traefik v${TRAEFIK_VERSION} (${ARCH})"
download_dir=$(mktemp -d)
trap 'rm -r -- "$download_dir"' EXIT

curl -fsSL \
  "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_${ARCH}.tar.gz" \
  -o "$download_dir/traefik.tar.gz"

tar -xzf "$download_dir/traefik.tar.gz" -C "$download_dir" traefik

sudo install -m 0755 "$download_dir/traefik" /usr/bin/traefik

echo "==> Traefik installed: $(traefik version 2>&1 | head -1)"
