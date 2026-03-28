#!/usr/bin/env bash
# scripts/pre-commit-check.sh — Block unencrypted secrets from being committed
#
# sops-encrypted YAML files contain a "sops:" metadata key.
# If a secrets file is staged for commit without it, block the commit.
#
# Install: ln -sf ../../scripts/pre-commit-check.sh .git/hooks/pre-commit

FAIL=0
for f in $(git diff --cached --name-only | grep '^secrets/.*\.yaml$'); do
  [ -f "$f" ] || continue
  if ! git show ":$f" | grep -q "^sops:"; then
    echo "BLOCKED: $f is UNENCRYPTED. Run:"
    echo "  sops --encrypt --in-place $f"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Commit aborted. Encrypt all secrets files before committing."
  exit 1
fi
