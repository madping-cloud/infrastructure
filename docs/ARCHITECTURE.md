# Infrastructure Architecture

## Overview

Pull-based GitOps on Debian hosts running Incus containers.
NixOS runs **inside** containers — the Debian hosts use nix as a package manager only.

Each host runs a systemd timer that pulls the repo every 5 minutes and deploys any containers
defined in `machines/<hostname>.yaml` if there are new commits.

## Stack

```
GitHub (madping-cloud/infrastructure)
        │
        │  git pull (systemd timer, every 5 minutes)
        ▼
┌───────────────────┐     ┌───────────────────────────────┐
│  Thor             │     │  Loki (ZimaBoard)             │
│  Debian + Incus   │     │  Debian + Incus               │
│  10.100.0.1       │     │  TBD                          │
│                   │     │                               │
│  gitops-pull.timer│     │  gitops-pull.timer            │
│  /opt/infra       │     │  /opt/infra                   │
│                   │     │                               │
│  Incus containers:│     │  Incus containers:            │
│  ├── silas        │     │  └── (future agents)          │
│  ├── aurora       │     │                               │
│  └── atlas        │     │                               │
└───────────────────┘     └───────────────────────────────┘
```

## GitOps Pull Flow

```
1. Developer pushes to master
        │
        ▼
2. gitops-pull.timer fires on each host (every 5 min)
        │
        ▼
3. gitops-pull.sh runs:
   a. git fetch + reset --hard origin/master
   b. Compare OLD_COMMIT vs NEW_COMMIT
   c. If no change → exit (skip deploy)
   d. If changed → read machines/<hostname>.yaml
   e. For each container:
      - incus file push (sync flake)
      - incus exec nixos-rebuild switch --flake /etc/nixos#<container>
        │
        ▼
4. Logs to systemd journal (journalctl -u gitops-pull)
```

## Directory Structure

```
infrastructure/
├── flake.nix                    # Entry point — pins nixpkgs, defines nixosConfigurations
├── flake.lock                   # Pinned dependency hashes
│
├── machines/                    # Host-level config (what containers each host runs)
│   ├── thor.yaml                # Thor's container list
│   └── loki.yaml                # Loki's container list (add when provisioned)
│
├── modules/
│   ├── common/
│   │   └── default.nix          # Shared: locale, SSH, nix settings, firewall
│   └── services/
│       └── openclaw.nix         # OpenClaw systemd service module
│
├── hosts/
│   ├── _template/
│   │   └── default.nix          # Template for new agent containers
│   ├── silas/default.nix
│   ├── aurora/default.nix
│   └── atlas/default.nix
│
├── lib/
│   └── default.nix              # Shared helpers: mkAgent, mkContainer
│
├── secrets/
│   ├── .gitignore               # Prevents committing raw secrets
│   ├── thor/secrets.yaml        # sops-encrypted secrets for Thor containers
│   └── loki/secrets.yaml        # sops-encrypted secrets for Loki containers
│
├── systemd/
│   ├── gitops-pull.service      # Systemd service unit (installed on Debian hosts)
│   └── gitops-pull.timer        # Systemd timer unit (fires every 5 minutes)
│
├── scripts/
│   ├── deploy.sh                # Manual deploy via incus exec (run from host)
│   ├── gitops-pull.sh           # Pull-and-deploy (called by systemd timer)
│   └── bootstrap-host.sh        # One-time host setup script
│
├── deploy/
│   ├── colmena.nix              # Colmena deployment config (SSH-based)
│   └── scripts/
│       └── deploy.sh            # Remote deploy via nixos-rebuild --target-host
│
└── docs/
    └── ARCHITECTURE.md          # This file
```

## Workflows

### Bootstrapping a New Host (one-time)

```bash
# Run as root on the new Debian host
./scripts/bootstrap-host.sh <hostname>
```

What it does:
1. Installs nix (daemon mode) if not present
2. Installs git, age, sops, jq via nix
3. Clones repo to `/opt/infrastructure`
4. Sets hostname via `hostnamectl`
5. Guides through age key + GitHub deploy key setup
6. Installs `gitops-pull.service` + `gitops-pull.timer`, enables both

### Adding a New Container

1. Copy `hosts/_template/` → `hosts/<name>/`
2. Set `hostName` in the new config
3. Add `nixosConfigurations.<name>` entry to `flake.nix`
4. Add to `machines/<host>.yaml` container list
5. `incus launch images:nixos/25.11 <name>` on the host
6. First deploy: `./scripts/deploy.sh <name>`
7. All future deploys: automatic via timer

### Day-to-Day Changes

```bash
# Edit config
vim hosts/silas/default.nix

# Push — hosts deploy automatically within 5 minutes
git add -A && git commit -m "feat: ..."
git push
```

### Manual Deploy

```bash
# Single container
./scripts/deploy.sh <container>

# All containers for this host
./scripts/deploy.sh --all

# Check timer / logs
systemctl status gitops-pull.timer
journalctl -u gitops-pull -f
```

### Deploy Scripts — Which to Use?

| Script | Run From | Method |
|--------|----------|--------|
| `scripts/deploy.sh` | Debian host directly | `incus exec` (local, no SSH) |
| `deploy/scripts/deploy.sh` | Anywhere with SSH | `nixos-rebuild --target-host` |
| `scripts/gitops-pull.sh` | Called by systemd timer | Automated, runs on commit |

## Secrets Management

Secrets use [sops-nix](https://github.com/Mic92/sops-nix) with age encryption.
Each host has its own age key at `/root/.config/sops/age/keys.txt`.
Public keys are registered in `.sops.yaml`.

```bash
# Generate key (one-time per host)
age-keygen -o /root/.config/sops/age/keys.txt

# Edit secrets (auto-decrypts, re-encrypts on save)
sops secrets/thor/secrets.yaml

# Decrypt to verify
sops --decrypt secrets/thor/secrets.yaml
```

## Network

| Host  | IP         | Role                          |
|-------|------------|-------------------------------|
| thor  | 10.100.0.1 | Incus bridge gateway          |
| loki  | TBD        | ZimaBoard, future Incus host  |
| silas | TBD        | NixOS container (agent)       |
| aurora| TBD        | NixOS container (agent)       |
| atlas | TBD        | NixOS container (agent)       |

## Roadmap

- [ ] Wire up sops-nix for secrets in containers
- [ ] Configure container IPs and update network table
- [ ] Set up loki when ZimaBoard is provisioned
- [ ] Add failure alerting (notify Discord on deploy failure)
- [ ] Container snapshot strategy for backups
- [ ] Fill in `deploy/colmena.nix` with real IPs for SSH-based deploys
