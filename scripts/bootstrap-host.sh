#!/usr/bin/env bash
# scripts/bootstrap-host.sh — One-time Debian + Incus host setup
#
# Sets up a host to participate in pull-based GitOps:
#   - Installs nix (if not present)
#   - Installs required tools via nix (git, age, sops)
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

[ -z "$HOSTNAME" ] && { echo "Usage: $0 <hostname>"; exit 1; }

echo "══════════════════════════════════════════════"
echo "  Bootstrap: $HOSTNAME"
echo "══════════════════════════════════════════════"

# 1. Install nix (if not present)
if ! command -v nix &>/dev/null; then
  echo "→ Installing nix (daemon mode)..."
  sh <(curl -L https://nixos.org/nix/install) --daemon
  # shellcheck source=/dev/null
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  echo "→ nix already installed ($(nix --version))"
fi

# 2. Install required tools via nix
echo "→ Installing tools (git, age, sops, jq)..."
nix profile install nixpkgs#git nixpkgs#age nixpkgs#sops nixpkgs#jq

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
  echo "  Option A — Generate a new key:"
  echo "    age-keygen -o $AGE_DIR/keys.txt"
  echo "    cat $AGE_DIR/keys.txt  # note the public key"
  echo ""
  echo "  Option B — Copy an existing key from another host:"
  echo "    scp user@source:~/.config/sops/age/keys.txt $AGE_DIR/keys.txt"
  echo ""
  echo "  Then add the PUBLIC key to .sops.yaml in the repo and commit."
  echo ""
else
  echo "→ Age key found at $AGE_DIR/keys.txt"
fi

# 6. GitHub deploy key guidance
if [ ! -f /root/.ssh/deploy_key ]; then
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  ACTION REQUIRED: GitHub deploy key"
  echo "══════════════════════════════════════════════"
  echo ""
  echo "  Generate a read-only deploy key:"
  echo "    ssh-keygen -t ed25519 -f /root/.ssh/deploy_key -N ''"
  echo "    cat /root/.ssh/deploy_key.pub"
  echo ""
  echo "  Add the public key to:"
  echo "    github.com/madping-cloud/infrastructure → Settings → Deploy keys"
  echo "    (read-only is sufficient)"
  echo ""
  echo "  Then configure git to use it:"
  echo "    git config -f $REPO_DIR/.git/config core.sshCommand \\"
  echo "      'ssh -i /root/.ssh/deploy_key -o StrictHostKeyChecking=no'"
  echo ""
else
  echo "→ Deploy key found at /root/.ssh/deploy_key"
fi

# 7. Install and enable the gitops-pull timer
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
