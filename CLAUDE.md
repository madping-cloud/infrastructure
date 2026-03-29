# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Pull-based GitOps infrastructure for NixOS containers on Debian hosts using Incus. Commits to `master` auto-deploy within ~1 minute via a systemd timer — no CI runners or webhooks.

## Architecture

**Hosts** (Debian + Incus): Thor (10.100.0.1), Loki (planned)
**Containers** (NixOS 25.11): cole, atlas (on Thor)

Every container's NixOS config is built from a module stack applied by `lib/default.nix`'s `mkAgent` helper:
1. `sops-nix` — secret decryption
2. `modules/common/default.nix` — base config (locale, firewall, packages, kernel hardening)
3. `modules/services/openclaw.nix` — OpenClaw AI agent service (361 lines, the core module)
4. `hosts/<name>/default.nix` — per-agent config (models, channels, allowlists)

Container-to-host mapping lives in `machines/<hostname>.yaml`. The flake defines `nixosConfigurations` entries using `mkAgent`.

## Deploy Flow

`systemd/gitops-pull.timer` → `scripts/gitops-pull.sh`:
1. `git fetch` + compare HEAD to origin/master (exit early if no changes)
2. `git merge --ff-only`
3. For each container in `machines/<hostname>.yaml`:
   - Tar flake/modules/hosts into container via `incus exec`
   - Push sops-encrypted secrets + age key
   - `nixos-rebuild switch --flake /etc/nixos#<container>`
4. Discord webhook alert on failure

## Common Commands

```bash
# Manual deploy (run on the host as root)
./scripts/deploy.sh cole              # single container
./scripts/deploy.sh --all             # all containers on this host
./scripts/deploy.sh cole --build-only # dry run

# Trigger the gitops timer manually
systemctl start gitops-pull

# Watch deploy logs
journalctl -u gitops-pull -f

# Test a nix build locally (no deploy)
nix build .#nixosConfigurations.cole.config.system.build.toplevel

# Edit secrets (auto-decrypts, re-encrypts on save)
sops secrets/thor/shared.yaml

# Add a new container (creates config, flake entry, secrets, launches it)
./scripts/add-container.sh <name>

# Enter dev shell (installs git, sops, age, jq, nixos-rebuild + pre-commit hook)
nix develop
```

## Secrets

Managed via sops-nix with age encryption. Key routing in `.sops.yaml`.

- **Shared keys**: `secrets/<hostname>/shared.yaml` (API keys shared across containers)
- **Per-container**: `secrets/<hostname>/<container>.yaml` (tokens, per-container API key overrides)
- **Age key** (on host): `/root/.config/sops/age/keys.txt`

Per-container keys override shared keys when both exist. The `openclaw.nix` module injects decrypted secrets into `openclaw.json`, `auth-profiles.json`, and `/run/openclaw-env` at deploy time.

A pre-commit hook (auto-installed by `nix develop`) blocks committing unencrypted secrets.

## Key Conventions

- All deploys are **fast-forward only** — keep master linear
- SSH is disabled in containers; use `incus exec <container> -- <command>`
- Nix sandbox is disabled (LXC incompatibility)
- OpenClaw config is fully declarative via `services.openclaw.*` options in host configs — the module regenerates `openclaw.json` from scratch on every deploy
- Structured logging format: `level= action= host= msg= key=value`
