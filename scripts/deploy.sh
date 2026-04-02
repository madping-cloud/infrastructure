#!/usr/bin/env bash
# scripts/deploy.sh — Rebuild and deploy NixOS configuration to a container

set -euo pipefail

WORKSPACE="${WORKSPACE:-/opt/infrastructure}"
BUILD_ONLY=""
DEPLOY_ALL=""
HOSTNAME=$(hostname)
MACHINE_FILE="$WORKSPACE/machines/${HOSTNAME}.yaml"

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

  # Preserve agent memory files before deploy
  local MEMORY_BACKUP="/tmp/openclaw-memory-${CONTAINER}"
  rm -rf "$MEMORY_BACKUP"
  if incus exec "$CONTAINER" -- test -d /var/lib/openclaw 2>/dev/null; then
    echo "==> Backing up memory files..."
    mkdir -p "$MEMORY_BACKUP"
    incus exec "$CONTAINER" -- bash -c '
      cd /var/lib/openclaw
      find . -path "*/memory/*.md" -o -name "MEMORY.md" | grep -v node_modules
    ' 2>/dev/null | while read -r f; do
      mkdir -p "$MEMORY_BACKUP/$(dirname "$f")"
      incus file pull "$CONTAINER/var/lib/openclaw/$f" "$MEMORY_BACKUP/$f" 2>/dev/null || true
    done
    local BACKED_UP
    BACKED_UP=$(find "$MEMORY_BACKUP" -name "*.md" 2>/dev/null | wc -l)
    echo "    $BACKED_UP memory file(s) backed up"
  fi

  # Sync nix config
  echo "==> Syncing configuration..."
  incus exec "$CONTAINER" -- mkdir -p /etc/nixos
  tar -C "$WORKSPACE" \
    --exclude='.git' --exclude='secrets' --exclude='scripts' --exclude='systemd' \
    --exclude='docs' --exclude='machines' --exclude='*.sh' \
    -cf - flake.nix flake.lock hosts modules lib .sops.yaml 2>/dev/null \
    | incus exec "$CONTAINER" -- tar -C /etc/nixos -xf -

  # Push age key
  AGE_KEY="/root/.config/sops/age/keys.txt"
  if [ -f "$AGE_KEY" ]; then
    echo "==> Pushing age key..."
    incus exec "$CONTAINER" -- mkdir -p /var/lib/sops-nix
    incus file push "$AGE_KEY" "$CONTAINER/var/lib/sops-nix/key.txt"
    incus exec "$CONTAINER" -- chmod 600 /var/lib/sops-nix/key.txt
  fi

  # Push secrets (only shared + container-specific, not other containers' secrets)
  if [ -d "$WORKSPACE/secrets/$HOSTNAME" ]; then
    echo "==> Pushing secrets..."
    incus exec "$CONTAINER" -- mkdir -p "/etc/nixos/secrets/$HOSTNAME"
    local secret_files=()
    [ -f "$WORKSPACE/secrets/$HOSTNAME/shared.yaml" ] && secret_files+=(shared.yaml)
    [ -f "$WORKSPACE/secrets/$HOSTNAME/$CONTAINER.yaml" ] && secret_files+=("$CONTAINER.yaml")
    if [ ${#secret_files[@]} -gt 0 ]; then
      tar -C "$WORKSPACE/secrets/$HOSTNAME" -cf - "${secret_files[@]}" \
        | incus exec "$CONTAINER" -- tar -C "/etc/nixos/secrets/$HOSTNAME" -xf -
    fi
  fi

  # Bootstrap prep (idempotent)
  echo "==> Prepping container..."
  incus exec "$CONTAINER" -- bash -c '
    if grep -q "sandbox = true" /etc/nix/nix.conf 2>/dev/null; then
      sed -i "s/sandbox = true/sandbox = false/" /etc/nix/nix.conf
      echo "  Nix sandbox disabled"
    fi
    rm -f /etc/nixos/configuration.nix /etc/nixos/incus.nix
  '

  # Build or switch
  if [[ -n "$BUILD_ONLY" ]]; then
    echo "==> Building (dry run)..."
    incus exec "$CONTAINER" -- nixos-rebuild build --flake "/etc/nixos#$CONTAINER"
    echo "==> Build OK. Run without --build-only to apply."
  else
    echo "==> Applying configuration..."
    incus exec "$CONTAINER" -- nixos-rebuild switch --flake "/etc/nixos#$CONTAINER"

    # Safety: ensure /run/current-system points to the correct store path
    incus exec "$CONTAINER" -- bash -c 'ln -sfn $(readlink -f /nix/var/nix/profiles/system) /run/current-system'

    # Restart openclaw-gateway to pick up new env/config from activation scripts
    if incus exec "$CONTAINER" -- systemctl is-active openclaw-gateway &>/dev/null; then
      echo "==> Restarting openclaw-gateway..."
      incus exec "$CONTAINER" -- systemctl restart openclaw-gateway
    fi

    # Restore memory files after deploy
    if [ -d "$MEMORY_BACKUP" ] && [ "$(find "$MEMORY_BACKUP" -name "*.md" 2>/dev/null | wc -l)" -gt 0 ]; then
      echo "==> Restoring memory files..."
      cd "$MEMORY_BACKUP"
      find . -name "*.md" | while read -r f; do
        local dest="/var/lib/openclaw/$f"
        incus exec "$CONTAINER" -- mkdir -p "$(dirname "$dest")"
        incus file push "$MEMORY_BACKUP/$f" "$CONTAINER$dest" 2>/dev/null || true
      done
      incus exec "$CONTAINER" -- bash -c 'chown -R openclaw:openclaw /var/lib/openclaw/' 2>/dev/null
      echo "    Memory restored"
      cd "$WORKSPACE"
    fi
    rm -rf "$MEMORY_BACKUP"

    echo "==> Deploy complete: $CONTAINER"
    incus exec "$CONTAINER" -- nixos-version
  fi
}

if [[ -n "$DEPLOY_ALL" ]]; then
  [ -f "$MACHINE_FILE" ] || { echo "ERROR: No machine file at $MACHINE_FILE"; exit 1; }
  CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)
  [ -z "$CONTAINERS" ] && { echo "No containers for $HOSTNAME"; exit 0; }
  echo "==> Deploying all: $(echo "$CONTAINERS" | tr '\n' ' ')"
  FAILURES=0
  for CONTAINER in $CONTAINERS; do
    deploy_container "$CONTAINER" || { echo "✗ $CONTAINER FAILED"; ((FAILURES+=1)); }
  done
  [ "$FAILURES" -gt 0 ] && { echo "==> $FAILURES failure(s)"; exit 1; }
  echo "==> All deployed"
elif [[ -n "$CONTAINER_NAME" ]]; then
  deploy_container "$CONTAINER_NAME"
else
  echo "Usage: $0 <container-name> [--build-only]"
  echo "       $0 --all [--build-only]"
  [ -f "$MACHINE_FILE" ] && { echo ""; echo "Containers:"; grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" | while read C; do echo "  - $C"; done; }
  exit 1
fi
