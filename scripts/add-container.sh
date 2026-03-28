#!/usr/bin/env bash
# scripts/add-container.sh — Create and deploy a new agent container

set -euo pipefail

REPO_DIR="/opt/infrastructure"
HOSTNAME=$(hostname)
MACHINE_FILE="$REPO_DIR/machines/${HOSTNAME}.yaml"

CONTAINER_NAME=""
NO_DEPLOY=""
for arg in "$@"; do
  case "$arg" in
    --no-deploy) NO_DEPLOY=1 ;;
    -*)          echo "Unknown option: $arg"; exit 1 ;;
    *)           CONTAINER_NAME="$arg" ;;
  esac
done

if [ -z "$CONTAINER_NAME" ]; then
  echo "Usage: $0 <container-name> [--no-deploy]"
  exit 1
fi

if ! echo "$CONTAINER_NAME" | grep -qP '^[a-z][a-z0-9-]*$'; then
  echo "ERROR: Container name must be lowercase, start with a letter, and contain only a-z, 0-9, hyphens"
  exit 1
fi

cd "$REPO_DIR"

# ── Step 1: Check for conflicts ──────────────────────────────────────────────
if [ -d "hosts/$CONTAINER_NAME" ]; then
  echo "ERROR: hosts/$CONTAINER_NAME/ already exists"
  exit 1
fi

if grep -q "\"$CONTAINER_NAME\"" flake.nix 2>/dev/null; then
  echo "ERROR: $CONTAINER_NAME already exists in flake.nix"
  exit 1
fi

echo "==> Creating container: $CONTAINER_NAME on $HOSTNAME"

# ── Step 2: Copy template and set hostname ───────────────────────────────────
echo "==> Setting up hosts/$CONTAINER_NAME/default.nix..."
cp -r hosts/_template "hosts/$CONTAINER_NAME"
sed -i "s/CHANGE_ME/$CONTAINER_NAME/g" "hosts/$CONTAINER_NAME/default.nix"

# ── Step 3: Add nixosConfigurations entry to flake.nix ───────────────────────
echo "==> Adding $CONTAINER_NAME to flake.nix..."
python3 - "$CONTAINER_NAME" << 'PYEOF'
import sys
name = sys.argv[1]
with open('flake.nix', 'r') as f:
    lines = f.readlines()
entry = (
    f'\n      # {name}\n'
    f'      {name} = mkAgent {{\n'
    f'        name       = "{name}";\n'
    f'        hostModule = ./hosts/{name}/default.nix;\n'
    f'      }};\n'
)
for i, line in enumerate(lines):
    if line.strip() == '};':
        lines.insert(i, entry)
        break
with open('flake.nix', 'w') as f:
    f.writelines(lines)
print(f"  Added {name} to nixosConfigurations")
PYEOF

# ── Step 4: Add to machines/<host>.yaml ──────────────────────────────────────
echo "==> Adding $CONTAINER_NAME to $MACHINE_FILE..."
if [ ! -f "$MACHINE_FILE" ]; then
  echo "ERROR: No machine file at $MACHINE_FILE"
  exit 1
fi
cat >> "$MACHINE_FILE" <<EOF
  - name: $CONTAINER_NAME
    flake_target: $CONTAINER_NAME
EOF

echo "==> Config files ready:"
echo "    - hosts/$CONTAINER_NAME/default.nix"
echo "    - flake.nix"
echo "    - $MACHINE_FILE"

# ── Step 4.5: Create encrypted secrets template ──────────────────────────────
SECRETS_FILE="$REPO_DIR/secrets/$HOSTNAME/$CONTAINER_NAME.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "==> Creating encrypted secrets template for $CONTAINER_NAME..."
  cat > "$SECRETS_FILE" <<'YAML'
discord_token: ""
telegram_token: ""
gateway_token: ""
anthropic_api_key: ""
openai_api_key: ""
google_ai_api_key: ""
groq_api_key: ""
openrouter_api_key: ""
YAML
  SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops --encrypt --in-place "$SECRETS_FILE" || {
    rm -f "$SECRETS_FILE"
    echo "ERROR: Failed to encrypt secrets template"
    exit 1
  }
  echo "    Created: $SECRETS_FILE"
  echo "    To set real values: cd $REPO_DIR && sops $SECRETS_FILE"
fi

if [ -n "$NO_DEPLOY" ]; then
  echo ""
  echo "==> --no-deploy: Skipping container launch and deploy."
  echo "    To finish later:"
  echo "      incus launch images:nixos/25.11 $CONTAINER_NAME"
  echo "      ./scripts/deploy.sh $CONTAINER_NAME"
  exit 0
fi

# ── Step 5: Launch Incus container ───────────────────────────────────────────
if incus info "$CONTAINER_NAME" &>/dev/null; then
  echo "==> Container $CONTAINER_NAME already exists in Incus"
else
  echo "==> Launching Incus container: $CONTAINER_NAME..."
  incus launch images:nixos/25.11 "$CONTAINER_NAME"

  echo "==> Waiting for container to start..."
  for i in $(seq 1 30); do
    if incus exec "$CONTAINER_NAME" -- true 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if ! incus exec "$CONTAINER_NAME" -- true 2>/dev/null; then
    echo "ERROR: Container $CONTAINER_NAME failed to start after 30s"
    exit 1
  fi
fi

# ── Step 6: Deploy ───────────────────────────────────────────────────────────
echo "==> Deploying NixOS config to $CONTAINER_NAME..."
./scripts/deploy.sh "$CONTAINER_NAME"

echo ""
echo "==> Done! Container $CONTAINER_NAME is running."
echo "    IP: $(incus list "$CONTAINER_NAME" -f csv -c 4 | cut -d' ' -f1)"
echo ""
echo "    Next steps:"
echo "      git add -A && git commit -m 'feat: add $CONTAINER_NAME container'"
echo "      git push"
