#!/bin/bash
set -euo pipefail
echo "==> Cleaning up"

# Clean package caches.
sudo dnf clean all
sudo rm -rf /var/cache/dnf

# Remove temporary files.
sudo rm -rf /tmp/*

# Clear cloud-init state so it runs fresh on new instances.
sudo cloud-init clean --logs

# Clear shell history.
cat /dev/null > ~/.bash_history
history -c

echo "==> Cleanup complete"
