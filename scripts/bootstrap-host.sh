#!/usr/bin/env bash
# scripts/bootstrap-host.sh — One-time Debian + Incus host setup
#
# Sets up a host to participate in pull-based GitOps:
#   - Installs required tools via apt (git, age, jq) + sops binary
#   - Clones/updates the infrastructure repo to /opt/infrastructure
#   - Sets the hostname
#   - Guides through age key and deploy key setup
#   - Installs and enables the gitops-pull.timer
#
# Usage:
#   ./scripts/bootstrap-host.sh <hostname>
#   curl -sL <raw-github-url>/scripts/bootstrap-host.sh | bash -s <hostname>

set -euo pipefail

HOSTNAME="${1:-}"
REPO="https://github.com/madping-cloud/infrastructure.git"
REPO_DIR="/opt/infrastructure"
SOPS_VERSION="3.9.4"

[ -z "$HOSTNAME" ] && { echo "Usage: $0 <hostname>"; exit 1; }

echo "══════════════════════════════════════════════"
echo "  Bootstrap: $HOSTNAME"
echo "══════════════════════════════════════════════"

# 1. Install tools via apt
echo "→ Installing tools (git, age, jq)..."
apt-get update -qq
apt-get install -y -qq git age jq curl

# 2. Install sops (no apt package, grab the binary)
if ! command -v sops &>/dev/null; then
  echo "→ Installing sops v${SOPS_VERSION}..."
  curl -sLO "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
  chmod +x "sops-v${SOPS_VERSION}.linux.amd64"
  mv "sops-v${SOPS_VERSION}.linux.amd64" /usr/local/bin/sops
else
  echo "→ sops already installed ($(sops --version))"
fi

# 3. Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  echo "→ Repo already exists at $REPO_DIR, pulling latest..."
  cd "$REPO_DIR" && git pull
else
  echo "→ Cloning repo to $REPO_DIR..."
  git clone "$REPO" "$REPO_DIR"
fi

# 4. Set hostname
echo "→ Setting hostname to $HOSTNAME..."
hostnamectl set-hostname "$HOSTNAME"

# 5. Age key guidance
AGE_DIR="/root/.config/sops/age"
mkdir -p "$AGE_DIR"
if [ ! -f "$AGE_DIR/keys.txt" ]; then
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  ACTION REQUIRED: Age encryption key"
  echo "══════════════════════════════════════════════"
  echo ""
  echo "  Generate a new key:"
  echo "    age-keygen -o $AGE_DIR/keys.txt"
  echo "    cat $AGE_DIR/keys.txt  # note the public key"
  echo ""
  echo "  Then add the PUBLIC key to .sops.yaml in the repo and commit."
  echo ""
else
  echo "→ Age key found at $AGE_DIR/keys.txt"
fi

# 6. Install and enable the gitops-pull timer
echo "→ Installing gitops-pull systemd units..."
cp "$REPO_DIR/systemd/gitops-pull.service" /etc/systemd/system/
cp "$REPO_DIR/systemd/gitops-pull.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gitops-pull.timer

echo ""
echo "══════════════════════════════════════════════"
echo "  ✓ Bootstrap complete: $HOSTNAME"
echo ""
echo "  Timer status:  systemctl status gitops-pull.timer"
echo "  Live logs:     journalctl -u gitops-pull -f"
echo "  Manual run:    systemctl start gitops-pull"
echo "  Machine file:  $REPO_DIR/machines/$HOSTNAME.yaml"
echo "══════════════════════════════════════════════"
