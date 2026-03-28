#!/usr/bin/env bash
# scripts/gitops-pull.sh — Pull-based GitOps deploy script
#
# Called by the gitops-pull.timer systemd timer on each Debian host.
# Pulls the latest infrastructure repo, checks for changes, and deploys
# any containers defined in machines/<hostname>.yaml if there are new commits.
#
# Logs to systemd journal via logger (SyslogIdentifier=gitops-pull).
# Prevent concurrent runs with a lockfile.

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
# Matches lines like:  "  - name: silas"
CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)

if [ -z "$CONTAINERS" ]; then
  logger -t "$LOG_TAG" "No containers defined for $HOSTNAME, nothing to deploy"
  exit 0
fi

# Deploy each container
FAILURES=0
for CONTAINER in $CONTAINERS; do
  logger -t "$LOG_TAG" "Deploying $CONTAINER..."

  # Check container is running
  if incus exec "$CONTAINER" -- true 2>/dev/null; then
    # Sync flake into container
    incus file push -r "$REPO_DIR/." "$CONTAINER/etc/nixos/" --create-dirs 2>/dev/null

    if incus exec "$CONTAINER" -- nixos-rebuild switch --flake "/etc/nixos#$CONTAINER" 2>&1 | logger -t "$LOG_TAG"; then
      logger -t "$LOG_TAG" "✓ $CONTAINER deployed successfully"
    else
      logger -t "$LOG_TAG" "✗ $CONTAINER deploy FAILED"
      ((FAILURES++))
    fi
  else
    logger -t "$LOG_TAG" "✗ $CONTAINER is not running, skipping"
    ((FAILURES++))
  fi
done

if [ "$FAILURES" -gt 0 ]; then
  logger -t "$LOG_TAG" "Completed with $FAILURES failure(s)"
  exit 1
fi

logger -t "$LOG_TAG" "All containers deployed successfully (${NEW_COMMIT:0:8})"
