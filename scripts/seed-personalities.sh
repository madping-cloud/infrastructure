#!/usr/bin/env bash
# Seed personality files to containers — only if file does not already exist
# Called by gitops-pull.sh after NixOS deploy

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERSONALITIES_DIR="$REPO_DIR/personalities"

if [[ ! -d "$PERSONALITIES_DIR" ]]; then
  echo "[personality-seed] No personalities/ dir found, skipping"
  exit 0
fi

for agent_dir in "$PERSONALITIES_DIR"/*/; do
  agent=$(basename "$agent_dir")

  # Check container is running
  if ! incus info "$agent" &>/dev/null; then
    echo "[personality-seed] Container $agent not found, skipping"
    continue
  fi

  status=$(incus info "$agent" | grep -i "Status:" | awk '{print $2}')
  if [[ "$status" != "Running" ]]; then
    echo "[personality-seed] Container $agent not running (status: $status), skipping"
    continue
  fi

  for file in "$agent_dir"*; do
    filename=$(basename "$file")
    dest="/var/lib/openclaw/workspace/$filename"

    # Only push if file doesn't already exist on container
    if incus exec "$agent" -- test -f "$dest" 2>/dev/null; then
      echo "[personality-seed] $agent/$filename already exists, skipping"
    else
      echo "[personality-seed] Seeding $agent/$filename"
      incus file push "$file" "$agent$dest"
    fi
  done
done

echo "[personality-seed] Done"
