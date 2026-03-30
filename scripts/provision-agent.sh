#!/usr/bin/env bash
# scripts/provision-agent.sh — Physically provision a container that already has
# a host config in the repo (flake.nix + hosts/<name>/default.nix).
#
# Use this when the infra PR has already been merged but the container doesn't
# physically exist yet on this host. For brand-new containers (no repo config),
# use add-container.sh instead.
#
# Usage:
#   ./scripts/provision-agent.sh <container-name> [--no-personality] [--dry-run]
#
# What it does:
#   1. Validates the container config exists in the repo
#   2. Launches the Incus container (NixOS 25.11) if it doesn't exist
#   3. Creates a secrets file if missing (opens sops for you to fill in real values)
#   4. Deploys via deploy.sh (pushes config, age key, secrets, runs nixos-rebuild)
#   5. Syncs personality files from madping-cloud/personalities (unless --no-personality)
#
# Run from: Thor (root), with /opt/infrastructure as the repo dir

set -euo pipefail

REPO_DIR="/opt/infrastructure"
PERSONALITIES_REPO="https://github.com/madping-cloud/personalities.git"
PERSONALITIES_DIR="/tmp/personalities-sync"
HOSTNAME=$(hostname)
MACHINE_FILE="$REPO_DIR/machines/${HOSTNAME}.yaml"
MANAGED_PERSONALITY_FILES=("SOUL.md" "IDENTITY.md" "AGENTS.md" "USER.md" "TOOLS.md")
WORKSPACE="/var/lib/openclaw/workspace"

CONTAINER_NAME=""
NO_PERSONALITY=""
DRY_RUN=""

for arg in "$@"; do
  case "$arg" in
    --no-personality) NO_PERSONALITY=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -*)               echo "Unknown option: $arg"; exit 1 ;;
    *)                CONTAINER_NAME="$arg" ;;
  esac
done

if [ -z "$CONTAINER_NAME" ]; then
  echo "Usage: $0 <container-name> [--no-personality] [--dry-run]"
  echo ""
  echo "Options:"
  echo "  --no-personality  Skip personality file sync after deploy"
  echo "  --dry-run         Print what would happen, don't do it"
  exit 1
fi

if ! echo "$CONTAINER_NAME" | grep -qP '^[a-z][a-z0-9-]*$'; then
  echo "ERROR: Container name must be lowercase, letters/numbers/hyphens only"
  exit 1
fi

log() { echo "==> $*"; }
dry() { [ -n "$DRY_RUN" ] && echo "    [dry-run] $*" || true; }

# ── Step 1: Validate config exists in repo ───────────────────────────────────
log "Checking repo config for '$CONTAINER_NAME'..."

if [ ! -f "$REPO_DIR/hosts/$CONTAINER_NAME/default.nix" ]; then
  echo "ERROR: No config found at $REPO_DIR/hosts/$CONTAINER_NAME/default.nix"
  echo "       Either the PR hasn't merged yet, or use add-container.sh for new containers."
  exit 1
fi

if ! grep -q "\"$CONTAINER_NAME\"\|name.*=.*\"$CONTAINER_NAME\"" "$REPO_DIR/flake.nix" 2>/dev/null; then
  echo "WARNING: $CONTAINER_NAME not found in flake.nix — deploy may fail"
fi

echo "    Found: hosts/$CONTAINER_NAME/default.nix ✓"

# ── Step 2: Launch container if it doesn't exist ─────────────────────────────
log "Checking Incus container..."

if incus info "$CONTAINER_NAME" &>/dev/null; then
  CONTAINER_STATUS=$(incus info "$CONTAINER_NAME" | grep "^Status:" | awk '{print $2}')
  echo "    Container exists (status: $CONTAINER_STATUS)"
  if [ "$CONTAINER_STATUS" != "RUNNING" ]; then
    log "Starting container..."
    [ -z "$DRY_RUN" ] && incus start "$CONTAINER_NAME" || dry "incus start $CONTAINER_NAME"
  fi
else
  log "Launching new container from NixOS 25.11..."
  dry "incus launch images:nixos/25.11 $CONTAINER_NAME"
  if [ -z "$DRY_RUN" ]; then
    incus launch images:nixos/25.11 "$CONTAINER_NAME"
    log "Waiting for container to boot..."
    for i in $(seq 1 30); do
      incus exec "$CONTAINER_NAME" -- true 2>/dev/null && break
      echo -n "."; sleep 1
    done
    echo ""
    incus exec "$CONTAINER_NAME" -- true 2>/dev/null || {
      echo "ERROR: Container failed to start within 30s"
      exit 1
    }
  fi
fi

# ── Step 3: Secrets ───────────────────────────────────────────────────────────
SECRETS_FILE="$REPO_DIR/secrets/$HOSTNAME/$CONTAINER_NAME.yaml"

log "Checking secrets..."

if [ ! -f "$SECRETS_FILE" ]; then
  log "No secrets file found — creating template at $SECRETS_FILE"
  log "You'll need to fill in real values with: sops $SECRETS_FILE"

  if [ -z "$DRY_RUN" ]; then
    mkdir -p "$(dirname "$SECRETS_FILE")"

    # Write plaintext template first
    TEMP_SECRETS=$(mktemp)
    cat > "$TEMP_SECRETS" << 'YAML'
discord_token: "FILL_ME_IN"
gateway_token: "FILL_ME_IN"
anthropic_api_key: "FILL_ME_IN"
openai_api_key: "FILL_ME_IN"
google_ai_api_key: "FILL_ME_IN"
groq_api_key: "FILL_ME_IN"
openrouter_api_key: "FILL_ME_IN"
YAML

    # Encrypt with sops
    SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
      sops --encrypt --input-type yaml --output-type yaml "$TEMP_SECRETS" > "$SECRETS_FILE" || {
        rm -f "$TEMP_SECRETS" "$SECRETS_FILE"
        echo "ERROR: sops encrypt failed — is SOPS configured on this host?"
        exit 1
      }
    rm -f "$TEMP_SECRETS"
    echo "    Template created. Opening for editing..."
    SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops "$SECRETS_FILE"
  else
    dry "Would create and open: $SECRETS_FILE"
  fi
else
  echo "    Secrets file exists: $SECRETS_FILE ✓"

  # Check for unfilled placeholders
  if SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops -d "$SECRETS_FILE" 2>/dev/null | grep -q "FILL_ME_IN"; then
    echo ""
    echo "WARNING: Secrets file still has FILL_ME_IN placeholders."
    echo "         Opening for editing..."
    SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops "$SECRETS_FILE"
  fi
fi

# ── Step 4: Deploy ────────────────────────────────────────────────────────────
log "Deploying NixOS config to $CONTAINER_NAME..."

if [ -z "$DRY_RUN" ]; then
  cd "$REPO_DIR"
  ./scripts/deploy.sh "$CONTAINER_NAME"
else
  dry "./scripts/deploy.sh $CONTAINER_NAME"
fi

# ── Step 5: Personality files ─────────────────────────────────────────────────
if [ -n "$NO_PERSONALITY" ]; then
  log "Skipping personality sync (--no-personality)"
else
  log "Syncing personality files from madping-cloud/personalities..."

  if [ -z "$DRY_RUN" ]; then
    # Clone or pull personalities repo
    if [ -d "$PERSONALITIES_DIR/.git" ]; then
      git -C "$PERSONALITIES_DIR" pull --ff-only --quiet
    else
      git clone --quiet "$PERSONALITIES_REPO" "$PERSONALITIES_DIR"
    fi

    AGENT_DIR="$PERSONALITIES_DIR/agents/$CONTAINER_NAME"
    if [ ! -d "$AGENT_DIR" ]; then
      echo "WARNING: No personality files found for '$CONTAINER_NAME' in personalities repo"
      echo "         Expected: agents/$CONTAINER_NAME/ — skipping personality sync"
    else
      for file in "${MANAGED_PERSONALITY_FILES[@]}"; do
        src="$AGENT_DIR/$file"
        if [ -f "$src" ]; then
          incus exec "$CONTAINER_NAME" -- \
            bash -c "mkdir -p $WORKSPACE && tee $WORKSPACE/$file" < "$src" > /dev/null
          echo "    ✓ $file"
        else
          echo "    - $file (not in personalities repo, skipping)"
        fi
      done
      echo "    Personality sync complete"
    fi
  else
    dry "Clone/pull madping-cloud/personalities"
    dry "Sync agents/$CONTAINER_NAME/{SOUL,IDENTITY,AGENTS,USER,TOOLS}.md → $WORKSPACE/"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✓ $CONTAINER_NAME is provisioned"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "$DRY_RUN" ]; then
  echo " IP:     $(incus list "$CONTAINER_NAME" -f csv -c 4 2>/dev/null | cut -d' ' -f1 || echo 'unknown')"
  echo " Status: $(incus info "$CONTAINER_NAME" 2>/dev/null | grep '^Status:' | awk '{print $2}' || echo 'unknown')"
fi
echo ""
echo " Next steps:"
echo "   - Check OpenClaw: incus exec $CONTAINER_NAME -- systemctl status openclaw-gateway"
echo "   - View logs:      incus exec $CONTAINER_NAME -- journalctl -u openclaw-gateway -f"
if [ -n "$DRY_RUN" ]; then
  echo ""
  echo " (dry-run — nothing was changed)"
fi
