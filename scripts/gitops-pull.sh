#!/usr/bin/env bash
# scripts/gitops-pull.sh — Pull-based GitOps deploy script
#
# Called by the gitops-pull.timer systemd timer on each Debian host.
# Pulls the latest infrastructure repo, checks for changes, and deploys
# any containers defined in machines/<hostname>.yaml if there are new commits.
#
# Logs to systemd journal via logger (SyslogIdentifier=gitops-pull).
# Prevents concurrent runs with a lockfile.

set -euo pipefail

REPO_DIR="/opt/infrastructure"
HOSTNAME=$(hostname)
MACHINE_FILE="$REPO_DIR/machines/${HOSTNAME}.yaml"
LOCK_FILE="/tmp/gitops-pull.lock"
LOG_TAG="gitops-pull"

# Prevent concurrent runs
exec 200>"$LOCK_FILE"
flock -n 200 || { logger -t "$LOG_TAG" "Already running, skipping"; exit 0; }

# Record current commit
cd "$REPO_DIR"
OLD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "none")

# Pull latest
logger -t "$LOG_TAG" "Pulling latest from origin/master..."
git fetch origin master --quiet
git reset --hard origin/master --quiet

NEW_COMMIT=$(git rev-parse HEAD)

# Skip if no changes
if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
  logger -t "$LOG_TAG" "No changes (${NEW_COMMIT:0:8}), skipping deploy"
  exit 0
fi

logger -t "$LOG_TAG" "New commits: ${OLD_COMMIT:0:8} -> ${NEW_COMMIT:0:8}"

# Check machine file exists
if [ ! -f "$MACHINE_FILE" ]; then
  logger -t "$LOG_TAG" "ERROR: No machine file at $MACHINE_FILE"
  exit 1
fi

# Parse containers from YAML (simple grep — no yq dependency required)
# Matches lines like:  "  - name: cole"
CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)

if [ -z "$CONTAINERS" ]; then
  logger -t "$LOG_TAG" "No containers defined for $HOSTNAME, nothing to deploy"
  exit 0
fi

# Sync only the nix config files to each container (not .git, secrets, scripts, etc.)
sync_config() {
  local container="$1"
  local dest="/etc/nixos"

  logger -t "$LOG_TAG" "Syncing nix config to $container:$dest..."

  # Ensure destination exists
  incus exec "$container" -- mkdir -p "$dest"

  # Use tar to reliably push only what nix needs
  tar -C "$REPO_DIR" \
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
    | incus exec "$container" -- tar -C "$dest" -xf -

  # Push only this host's secrets to the container
  if [ -d "$REPO_DIR/secrets/$HOSTNAME" ]; then
    incus exec "$container" -- mkdir -p "$dest/secrets/$HOSTNAME"
    tar -C "$REPO_DIR/secrets/$HOSTNAME" -cf - . \
      | incus exec "$container" -- tar -C "$dest/secrets/$HOSTNAME" -xf -
  fi

  # Push age key (sops-nix needs this to decrypt secrets)
  AGE_KEY="/root/.config/sops/age/keys.txt"
  if [ -f "$AGE_KEY" ]; then
    incus exec "$container" -- mkdir -p /var/lib/sops-nix
    incus file push "$AGE_KEY" "$container/var/lib/sops-nix/key.txt"
    incus exec "$container" -- chmod 600 /var/lib/sops-nix/key.txt
  fi

  logger -t "$LOG_TAG" "Sync complete for $container"
}

# Deploy each container
FAILURES=0
SKIPPED=0
for CONTAINER in $CONTAINERS; do
  logger -t "$LOG_TAG" "Deploying $CONTAINER..."

  # Check container exists and is running
  if ! incus exec "$CONTAINER" -- true 2>/dev/null; then
    logger -t "$LOG_TAG" "⊘ $CONTAINER is not running, skipping"
    ((SKIPPED++))
    continue
  fi

  # Sync nix config into container
  sync_config "$CONTAINER"

  # Bootstrap prep: idempotent, no-op on already-deployed containers
  incus exec "$CONTAINER" -- bash -c '
    grep -q "sandbox = true" /etc/nix/nix.conf 2>/dev/null && \
      sed -i "s/sandbox = true/sandbox = false/" /etc/nix/nix.conf || true
    rm -f /etc/nixos/configuration.nix /etc/nixos/incus.nix
  ' 2>/dev/null || true

  if incus exec "$CONTAINER" -- nixos-rebuild switch --flake "/etc/nixos#$CONTAINER" 2>&1 | logger -t "$LOG_TAG"; then
    logger -t "$LOG_TAG" "✓ $CONTAINER deployed successfully"
  else
    logger -t "$LOG_TAG" "✗ $CONTAINER deploy FAILED"
    ((FAILURES++))
  fi
done

if [ "$FAILURES" -gt 0 ]; then
  logger -t "$LOG_TAG" "Completed with $FAILURES failure(s), $SKIPPED skipped"
  exit 1
fi

if [ "$SKIPPED" -gt 0 ]; then
  logger -t "$LOG_TAG" "All reachable containers deployed (${NEW_COMMIT:0:8}), $SKIPPED not running"
else
  logger -t "$LOG_TAG" "All containers deployed successfully (${NEW_COMMIT:0:8})"
fi
