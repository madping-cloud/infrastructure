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
  echo "ERROR: Name must be lowercase, start with a letter, a-z/0-9/hyphens only"
  exit 1
fi

cd "$REPO_DIR"

if [ -d "hosts/$CONTAINER_NAME" ]; then
  echo "ERROR: hosts/$CONTAINER_NAME/ already exists"; exit 1
fi
if grep -q "\"$CONTAINER_NAME\"" flake.nix 2>/dev/null; then
  echo "ERROR: $CONTAINER_NAME already in flake.nix"; exit 1
fi

echo "==> Creating container: $CONTAINER_NAME on $HOSTNAME"

# ── Step 1: Copy template, set hostname, remove assertion guard ──────────────
echo "==> Setting up hosts/$CONTAINER_NAME/..."
cp -r hosts/_template "hosts/$CONTAINER_NAME"
sed -i "s/CHANGE_ME/$CONTAINER_NAME/g" "hosts/$CONTAINER_NAME/default.nix"
sed -i '/assertions/d' "hosts/$CONTAINER_NAME/default.nix"

# ── Step 2: Add to flake.nix (inside nixosConfigurations block) ──────────────
echo "==> Adding to flake.nix..."
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

# Find nixosConfigurations closing }; by counting braces
in_block = False
depth = 0
insert_at = None
for i, line in enumerate(lines):
    if 'nixosConfigurations' in line and '{' in line:
        in_block = True
        depth = 1
        continue
    if in_block:
        depth += line.count('{') - line.count('}')
        if depth <= 0:
            insert_at = i
            break

if insert_at is None:
    print("ERROR: Could not find nixosConfigurations closing"); sys.exit(1)

lines.insert(insert_at, entry)
with open('flake.nix', 'w') as f:
    f.writelines(lines)
print(f"  Added {name} to nixosConfigurations")
PYEOF

# ── Step 3: Add to machines yaml ─────────────────────────────────────────────
echo "==> Adding to $MACHINE_FILE..."
[ -f "$MACHINE_FILE" ] || { echo "ERROR: No machine file at $MACHINE_FILE"; exit 1; }
cat >> "$MACHINE_FILE" <<EOF
  - name: $CONTAINER_NAME
    flake_target: $CONTAINER_NAME
EOF

# ── Step 4: Create encrypted secrets template ────────────────────────────────
SECRETS_FILE="$REPO_DIR/secrets/$HOSTNAME/$CONTAINER_NAME.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "==> Creating encrypted secrets template..."
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
    rm -f "$SECRETS_FILE"; echo "ERROR: sops encrypt failed"; exit 1
  }
  echo "    Created: $SECRETS_FILE"
fi

echo "==> Config ready. Files:"
echo "    hosts/$CONTAINER_NAME/default.nix"
echo "    flake.nix"
echo "    $MACHINE_FILE"
echo "    $SECRETS_FILE"

if [ -n "$NO_DEPLOY" ]; then
  echo ""; echo "==> --no-deploy: done. To finish later:"
  echo "      incus launch images:nixos/25.11 $CONTAINER_NAME"
  echo "      ./scripts/deploy.sh $CONTAINER_NAME"
  exit 0
fi

# ── Step 5: Launch container ─────────────────────────────────────────────────
if incus info "$CONTAINER_NAME" &>/dev/null; then
  echo "==> Container already exists in Incus"
else
  echo "==> Launching container..."
  incus launch images:nixos/25.11 "$CONTAINER_NAME"
  echo "==> Waiting for boot..."
  for i in $(seq 1 30); do
    incus exec "$CONTAINER_NAME" -- true 2>/dev/null && break; sleep 1
  done
  incus exec "$CONTAINER_NAME" -- true 2>/dev/null || { echo "ERROR: Failed to start after 30s"; exit 1; }
fi

# ── Step 6: Deploy ───────────────────────────────────────────────────────────
echo "==> Deploying..."
./scripts/deploy.sh "$CONTAINER_NAME"

echo ""
echo "==> Done! Container $CONTAINER_NAME is running."
echo "    IP: $(incus list "$CONTAINER_NAME" -f csv -c 4 | cut -d' ' -f1)"
echo "    To add real secrets: cd $REPO_DIR && sops $SECRETS_FILE"
echo "    To commit: git add -A && git commit -m 'feat: add $CONTAINER_NAME'"
