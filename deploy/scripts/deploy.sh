#!/usr/bin/env bash
# deploy/scripts/deploy.sh — Deploy a NixOS config to an Incus container
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  RUN THIS FROM: Anywhere with SSH access to the target container        │
# │  METHOD: Uses `nixos-rebuild --target-host` over SSH                   │
# │                                                                         │
# │  Use this script when you are NOT on Thor and want to deploy remotely   │
# │  to a container via SSH. Requires nixos-rebuild in your local PATH.     │
# │                                                                         │
# │  For local deploys (from Thor via incus exec), use: scripts/deploy.sh  │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Usage:
#   ./deploy/scripts/deploy.sh <hostname> [--build-only] [--dry-run]
#
# Examples:
#   ./deploy/scripts/deploy.sh workbench           # build + activate
#   ./deploy/scripts/deploy.sh workbench --build-only  # build only (no switch)
#   ./deploy/scripts/deploy.sh workbench --dry-run     # dry-run (show diff)
#
# Requirements:
#   - nixos-rebuild in PATH (or nix run nixpkgs#nixos-rebuild)
#   - SSH access to the target container
#   - Container must be running NixOS

set -euo pipefail

HOSTNAME="${1:-}"
BUILD_ONLY=false
DRY_RUN=false
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  echo "Usage: $0 <hostname> [--build-only] [--dry-run]"
  echo "Hosts: workbench, thor, zimaboard"
  exit 1
}

[[ -z "$HOSTNAME" ]] && usage

shift
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ;;
    --dry-run)    DRY_RUN=true ;;
    *) echo "Unknown flag: $arg"; usage ;;
  esac
done

# Map hostname to IP
declare -A HOST_IPS=(
  ["workbench"]="10.100.0.21"
  ["thor"]="10.100.0.1"
  ["zimaboard"]="UNCONFIGURED"
)

TARGET_IP="${HOST_IPS[$HOSTNAME]:-}"
[[ -z "$TARGET_IP" ]] && { echo "Unknown host: $HOSTNAME"; usage; }
[[ "$TARGET_IP" == "UNCONFIGURED" ]] && { echo "Host $HOSTNAME has no IP configured yet"; exit 1; }

echo "══════════════════════════════════════════════"
echo "  Deploy: $HOSTNAME ($TARGET_IP)"
echo "  Flake:  $FLAKE_DIR"
echo "  Mode:   $(${BUILD_ONLY} && echo 'build-only' || ${DRY_RUN} && echo 'dry-run' || echo 'switch')"
echo "══════════════════════════════════════════════"

# Build the config
echo "→ Building config for $HOSTNAME..."
nix build "${FLAKE_DIR}#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel" \
  --no-link \
  --print-out-paths

if $BUILD_ONLY; then
  echo "✓ Build successful (--build-only, not deploying)"
  exit 0
fi

# Deploy via nixos-rebuild
ACTION="switch"
$DRY_RUN && ACTION="dry-activate"

echo "→ Deploying to $HOSTNAME ($TARGET_IP) with action: $ACTION"
nixos-rebuild "$ACTION" \
  --flake "${FLAKE_DIR}#${HOSTNAME}" \
  --target-host "root@${TARGET_IP}" \
  --use-remote-sudo

echo "✓ Deploy complete: $HOSTNAME"
