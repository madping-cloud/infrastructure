#!/usr/bin/env bash
# scripts/add-agent-secrets.sh — Interactively create sops-encrypted secrets for a new agent.
#
# Run from: Thor (root), inside /opt/infrastructure
#
# Usage:
#   ./scripts/add-agent-secrets.sh <container-name>
#
# What it does:
#   1. Prompts for discord_token and telegram_token
#   2. Auto-generates a gateway_token (random hex)
#   3. Creates secrets/thor/<name>.yaml encrypted with the Thor age key
#   4. Commits and pushes to the repo

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOPS_KEY=/root/.config/sops/age/keys.txt

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <container-name>"
  exit 1
fi

NAME="$1"
SECRETS_FILE="$REPO_DIR/secrets/thor/${NAME}.yaml"

if [ -f "$SECRETS_FILE" ]; then
  echo "ERROR: $SECRETS_FILE already exists. Edit it directly with:"
  echo "  SOPS_AGE_KEY_FILE=$SOPS_KEY sops $SECRETS_FILE"
  exit 1
fi

echo ""
echo "Creating secrets for: $NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -rp "discord_token (or leave blank to skip): " DISCORD_TOKEN
read -rp "telegram_token (or leave blank to skip): " TELEGRAM_TOKEN

GATEWAY_TOKEN=$(openssl rand -hex 16)
echo "gateway_token: auto-generated ($GATEWAY_TOKEN)"

cd "$REPO_DIR"

cat > "$SECRETS_FILE" << YAML
discord_token: "${DISCORD_TOKEN}"
telegram_token: "${TELEGRAM_TOKEN}"
gateway_token: "${GATEWAY_TOKEN}"
anthropic_api_key: ""
openai_api_key: ""
google_ai_api_key: ""
groq_api_key: ""
openrouter_api_key: ""
YAML

SOPS_AGE_KEY_FILE=$SOPS_KEY sops --encrypt --in-place "$SECRETS_FILE"
echo ""
echo "✓ Encrypted: $SECRETS_FILE"

git add "$SECRETS_FILE"
git commit -m "secrets: add ${NAME}"
git push
echo "✓ Committed and pushed"
echo ""
echo "Next: run provision-agent.sh ${NAME} on Thor after the infra PR merges."
