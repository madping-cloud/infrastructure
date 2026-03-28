#!/usr/bin/env bash
# deploy.sh — Rebuild and deploy NixOS configuration to a container
# Usage: ./deploy.sh [container-name] [--build-only]

set -euo pipefail

CONTAINER_NAME="${1:-workbench}"
BUILD_ONLY="${2:-}"
WORKSPACE="/root/.openclaw/workspace/infrastructure"

echo "==> Deploying to container: $CONTAINER_NAME"

# 1. Sync flake files to container
echo "==> Syncing configuration..."
incus file push -r "$WORKSPACE/." "$CONTAINER_NAME/etc/nixos/" \
    --create-dirs

# 2. Build or switch
if [[ "$BUILD_ONLY" == "--build-only" ]]; then
    echo "==> Building (dry run — not switching)..."
    incus exec "$CONTAINER_NAME" -- \
        nixos-rebuild build --flake "/etc/nixos#$CONTAINER_NAME"
    echo "==> Build successful. Run without --build-only to apply."
else
    echo "==> Applying configuration..."
    incus exec "$CONTAINER_NAME" -- \
        nixos-rebuild switch --flake "/etc/nixos#$CONTAINER_NAME"
    echo "==> Deploy complete!"
fi

# 3. Show current version
echo "==> NixOS version:"
incus exec "$CONTAINER_NAME" -- nixos-version
