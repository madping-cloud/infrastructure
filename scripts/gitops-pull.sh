#!/usr/bin/env bash
# scripts/gitops-pull.sh — Pull-based GitOps deploy script

set -euo pipefail

REPO_DIR="/opt/infrastructure"
HOSTNAME=$(hostname)
MACHINE_FILE="$REPO_DIR/machines/${HOSTNAME}.yaml"
LOCK_FILE="/tmp/gitops-pull.lock"
LOG_TAG="gitops-pull"
SECRETS_FILE="$REPO_DIR/secrets/${HOSTNAME}/shared.yaml"

# Structured logging: level=INFO|WARN|ERROR action= msg= key=value ...
log() {
  local level="$1"; shift
  local action="$1"; shift
  local msg="$1"; shift
  # Quote each trailing key=value pair for SIEM-safe output
  local kv=""
  for arg in "$@"; do
    kv="$kv ${arg%%=*}=\"${arg#*=}\""
  done
  logger -t "$LOG_TAG" "level=\"$level\" action=\"$action\" host=\"$HOSTNAME\" msg=\"$msg\"$kv"
}

discord_alert() {
  local webhook
  webhook=$(sops -d --extract '["discord_webhook"]' "$SECRETS_FILE" 2>/dev/null) || return 0
  [ -z "$webhook" ] && return 0
  local payload
  payload=$(printf '%s' "$1" | jq -Rs '{content: .}') || return 0
  curl -sf -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook" >/dev/null 2>&1 || true
}

# ── Lock ──────────────────────────────────────────────────────────────────────
exec 200>"$LOCK_FILE"
flock -n 200 || { log INFO lock "Already running, skipping"; exit 0; }

# ── Fetch ─────────────────────────────────────────────────────────────────────
cd "$REPO_DIR"
OLD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "none")

log INFO fetch "Pulling latest from origin/master" commit_local="${OLD_COMMIT:0:8}"
git fetch origin master --quiet

NEW_COMMIT=$(git rev-parse origin/master)

if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
  log INFO fetch "No changes detected" commit="${NEW_COMMIT:0:8}"
  exit 0
fi

log INFO fetch "New commits available" commit_old="${OLD_COMMIT:0:8}" commit_new="${NEW_COMMIT:0:8}"

# ── Merge ─────────────────────────────────────────────────────────────────────
git merge --ff-only origin/master --quiet
MERGED_COMMIT=$(git rev-parse --short HEAD)
log INFO merge "Fast-forward merge complete" commit="$MERGED_COMMIT"

# ── Load containers ───────────────────────────────────────────────────────────
if [ ! -f "$MACHINE_FILE" ]; then
  log ERROR config "Machine file not found" path="$MACHINE_FILE"
  exit 1
fi

CONTAINERS=$(grep -oP '^\s+- name:\s+\K\S+' "$MACHINE_FILE" || true)
CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -w)

if [ -z "$CONTAINERS" ]; then
  log WARN config "No containers defined, nothing to deploy"
  exit 0
fi

log INFO deploy_start "Beginning deployment" containers="$CONTAINER_COUNT" targets="$(echo "$CONTAINERS" | tr '\n' ',')"

# ── Sync helper ───────────────────────────────────────────────────────────────
sync_config() {
  local container="$1"
  local dest="/etc/nixos"

  incus exec "$container" -- mkdir -p "$dest"

  tar -C "$REPO_DIR" \
    --exclude='.git' \
    --exclude='secrets' \
    --exclude='scripts' \
    --exclude='systemd' \
    --exclude='docs' \
    --exclude='machines' \
    --exclude='*.sh' \
    -cf - \
    flake.nix flake.lock hosts modules lib .sops.yaml 2>/dev/null \
    | incus exec "$container" -- tar -C "$dest" -xf -

  if [ -d "$REPO_DIR/secrets/$HOSTNAME" ]; then
    incus exec "$container" -- mkdir -p "$dest/secrets/$HOSTNAME"
    tar -C "$REPO_DIR/secrets/$HOSTNAME" -cf - . \
      | incus exec "$container" -- tar -C "$dest/secrets/$HOSTNAME" -xf -
  fi

  AGE_KEY="/root/.config/sops/age/keys.txt"
  if [ -f "$AGE_KEY" ]; then
    incus exec "$container" -- mkdir -p /var/lib/sops-nix
    incus file push "$AGE_KEY" "$container/var/lib/sops-nix/key.txt"
    incus exec "$container" -- chmod 600 /var/lib/sops-nix/key.txt
  fi
}

# ── Deploy loop ───────────────────────────────────────────────────────────────
FAILURES=0
SKIPPED=0
SUCCEEDED=0
for CONTAINER in $CONTAINERS; do

  if ! incus exec "$CONTAINER" -- true 2>/dev/null; then
    log WARN deploy_skip "Container not running" container="$CONTAINER"
    ((SKIPPED++))
    continue
  fi

  log INFO sync "Syncing config and secrets" container="$CONTAINER"
  sync_config "$CONTAINER"

  # Bootstrap prep: idempotent, no-op on already-deployed containers
  incus exec "$CONTAINER" -- bash -c '
    grep -q "sandbox = true" /etc/nix/nix.conf 2>/dev/null && \
      sed -i "s/sandbox = true/sandbox = false/" /etc/nix/nix.conf || true
    rm -f /etc/nixos/configuration.nix /etc/nixos/incus.nix
  ' 2>/dev/null || true

  log INFO rebuild "Running nixos-rebuild switch" container="$CONTAINER"

  # pipefail (line 4) propagates nixos-rebuild failure through the pipe to logger
  if incus exec "$CONTAINER" -- nixos-rebuild switch --flake "/etc/nixos#$CONTAINER" 2>&1 | logger -t "$LOG_TAG[$CONTAINER]"; then
    incus exec "$CONTAINER" -- bash -c 'ln -sfn $(readlink -f /nix/var/nix/profiles/system) /run/current-system' 2>/dev/null || true
    log INFO deploy_ok "Deploy succeeded" container="$CONTAINER" commit="${NEW_COMMIT:0:8}"
    ((SUCCEEDED++))
  else
    log ERROR deploy_fail "Deploy failed" container="$CONTAINER" commit="${NEW_COMMIT:0:8}"
    discord_alert "⚠️ **Deploy failed:** \`$CONTAINER\` on \`$HOSTNAME\` (${NEW_COMMIT:0:8})"
    ((FAILURES++))
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
if [ "$FAILURES" -gt 0 ]; then
  log ERROR deploy_end "Deployment finished with failures" succeeded="$SUCCEEDED" failed="$FAILURES" skipped="$SKIPPED" commit="${NEW_COMMIT:0:8}"
  discord_alert "🔴 **GitOps deploy finished with $FAILURES failure(s)** on \`$HOSTNAME\` (${NEW_COMMIT:0:8})"
  exit 1
fi

log INFO deploy_end "Deployment complete" succeeded="$SUCCEEDED" failed="0" skipped="$SKIPPED" commit="${NEW_COMMIT:0:8}"
