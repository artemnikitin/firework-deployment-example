#!/bin/bash
set -euo pipefail
echo "==> Cleaning up"

# Clean provider-image package caches.
if command -v dnf &>/dev/null; then
  sudo dnf clean all
  sudo rm -rf /var/cache/dnf
elif command -v apt-get &>/dev/null; then
  sudo apt-get clean -y
  sudo rm -rf /var/lib/apt/lists/*
fi

# Remove temporary files.
sudo rm -rf /tmp/*

# Clear cloud-init state so it runs fresh on new instances.
command -v cloud-init &>/dev/null && sudo cloud-init clean --logs

# Clear shell history.
cat /dev/null > ~/.bash_history
history -c

echo "==> Cleanup complete"
