#!/usr/bin/env bash
# scripts/deploy.sh — Rebuild and deploy NixOS configuration to a container
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  RUN THIS FROM: A Debian Incus host (Thor, Loki, etc.)                  │
# │  METHOD: Uses `incus exec` to run nixos-rebuild inside the container    │
# │                                                                         │
# │  Use this script for manual deploys. Day-to-day deploys happen          │
# │  automatically via the gitops-pull.timer on each host.                  │
# │                                                                         │
# │  For remote deploys (SSH-based), use: deploy/scripts/deploy.sh         │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Usage:
#   ./scripts/deploy.sh [container-name] [--build-only]
#   ./scripts/deploy.sh --all              # Deploy all containers for this host
#
# Container list is read from machines/<hostname>.yaml when using --all.

set -euo pipefail

WORKSPACE="${WORKSPACE:-/opt/infrastructure}"
BUILD_ONLY=""
DEPLOY_ALL=""
HOSTNAME=$(hostname)
MACHINE_FILE="$WORKSPACE/machines/${HOSTNAME}.yaml"

# Parse args
CONTAINER_NAME=""
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --all)        DEPLOY_ALL=1 ;;
    *)            CONTAINER_NAME="$arg" ;;
  esac
done

deploy_container() {
  local CONTAINER="$1"
  echo "==> Deploying to container: $CONTAINER"

  # Sync only nix-needed files to container (matching gitops-pull.sh pattern)
  echo "==> Syncing configuration..."
  incus exec "$CONTAINER" -- mkdir -p /etc/nixos

  tar -C "$WORKSPACE" \
    --exclude='.git' \
    --exclude='secrets' \
    --exclude='scripts' \
    --exclude='systemd' \
    --exclude='docs' \
    --exclude='machines' \
    --exclude='deploy' \
    --exclude='*.sh' \
    -cf - \
    flake.nix flake.lock hosts modules lib .sops.yaml 2>/dev/null \
    | incus exec "$CONTAINER" -- tar -C /etc/nixos -xf -

  # Push age key (needed for sops-nix to decrypt secrets at activation time)
  AGE_KEY="/root/.config/sops/age/keys.txt"
  if [ -f "$AGE_KEY" ]; then
    echo "==> Pushing age key..."
    incus exec "$CONTAINER" -- mkdir -p /var/lib/sops-nix
    incus file push "$AGE_KEY" "$CONTAINER/var/lib/sops-nix/key.txt"
    incus exec "$CONTAINER" -- chmod 600 /var/lib/sops-nix/key.txt
  fi

  # Push secrets (sops-encrypted; decrypted at activation time by sops-nix)
  if [ -d "$WORKSPACE/secrets/$HOSTNAME" ]; then
    echo "==> Pushing secrets..."
    incus exec "$CONTAINER" -- mkdir -p "/etc/nixos/secrets/$HOSTNAME"
    tar -C "$WORKSPACE/secrets/$HOSTNAME" -cf - . \
      | incus exec "$CONTAINER" -- tar -C "/etc/nixos/secrets/$HOSTNAME" -xf -
  fi

  # Bootstrap prep: disable nix sandbox (LXC cannot use kernel namespaces)
  # and remove default NixOS configs that conflict with flake-based deploys.
  # Idempotent — safe to run on already-deployed containers.
  echo "==> Prepping container..."
  incus exec "$CONTAINER" -- bash -c '
    if grep -q "sandbox = true" /etc/nix/nix.conf 2>/dev/null; then
      sed -i "s/sandbox = true/sandbox = false/" /etc/nix/nix.conf
      echo "  Nix sandbox disabled (LXC incompatible)"
    fi
    rm -f /etc/nixos/configuration.nix /etc/nixos/incus.nix
  '

  # Build or switch
  if [[ -n "$BUILD_ONLY" ]]; then
    echo "==> Building (dry run — not switching)..."
    incus exec "$CONTAINER" -- nixos-rebuild build --flake "/etc/nixos#$CONTAINER"
    echo "==> Build successful. Run without --build-only to apply."
  else
    echo "==> Applying configuration..."
    incus exec "$CONTAINER" -- nixos-rebuild switch --flake "/etc/nixos#$CONTAINER"
    echo "==> NixOS version:"
    incus exec "$CONTAINER" -- nixos-version
    echo "==> Deploy complete: $CONTAINER"
  fi
}

if [[ -n "$DEPLOY_ALL" ]]; then
  # Deploy all containers defined for this host
  if [ ! -f "$MACHINE_FILE" ]; then
    echo "ERROR: No machine file at $MACHINE_FILE"
    echo "       Is this host registered in machines/?"
    exit 1
  fi

  CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)

  if [ -z "$CONTAINERS" ]; then
    echo "No containers defined for $HOSTNAME in $MACHINE_FILE"
    exit 0
  fi

  echo "==> Deploying all containers for $HOSTNAME: $(echo $CONTAINERS | tr '\n' ' ')"
  FAILURES=0
  for CONTAINER in $CONTAINERS; do
    deploy_container "$CONTAINER" || { echo "✗ $CONTAINER FAILED"; ((FAILURES++)); }
  done

  if [ "$FAILURES" -gt 0 ]; then
    echo "==> Completed with $FAILURES failure(s)"
    exit 1
  fi
  echo "==> All containers deployed successfully"

elif [[ -n "$CONTAINER_NAME" ]]; then
  deploy_container "$CONTAINER_NAME"

else
  echo "Usage: $0 <container-name> [--build-only]"
  echo "       $0 --all [--build-only]"
  echo ""
  if [ -f "$MACHINE_FILE" ]; then
    CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)
    echo "Containers registered for $HOSTNAME:"
    for C in $CONTAINERS; do echo "  - $C"; done
  fi
  exit 1
fi
