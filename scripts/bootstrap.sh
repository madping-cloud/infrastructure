#!/usr/bin/env bash
# bootstrap.sh — One-time container setup
# Run this ONCE after launching a fresh NixOS container.
# After bootstrap, use deploy.sh for all subsequent changes.

set -euo pipefail

CONTAINER_NAME="${1:-workbench}"
WORKSPACE="${WORKSPACE:-/opt/infrastructure}"

echo "==> Bootstrapping NixOS container: $CONTAINER_NAME"

# 1. Verify container is running
if ! incus info "$CONTAINER_NAME" | grep -q "Status: RUNNING"; then
    echo "ERROR: Container $CONTAINER_NAME is not running"
    exit 1
fi

# 2. Push flake to container
echo "==> Copying flake to container..."
incus file push -r "$WORKSPACE/." "$CONTAINER_NAME/etc/nixos/" \
    --create-dirs

# 3. Enable flakes in the container (in case not already enabled)
incus exec "$CONTAINER_NAME" -- bash -c '
    mkdir -p /etc/nix
    grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || \
      echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
'

# 4. Initial nixos-rebuild switch
echo "==> Running initial nixos-rebuild switch..."
incus exec "$CONTAINER_NAME" -- \
    nixos-rebuild switch --flake "/etc/nixos#$CONTAINER_NAME"

echo "==> Bootstrap complete! Container $CONTAINER_NAME is configured."
echo "    Use deploy.sh for future changes."
