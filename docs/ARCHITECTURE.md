# Infrastructure Architecture

## Overview

Pull-based GitOps on Debian hosts running Incus containers.
NixOS runs **inside** containers — the Debian hosts use nix as a package manager only.

Each host runs a systemd timer that pulls the repo every 1 minute and deploys any containers
defined in `machines/<hostname>.yaml` if there are new commits.

## Stack

```
GitHub (madping-cloud/infrastructure)
        │
        │  git pull (systemd timer, every 1 minute)
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
│  ├── cole         │     │  └── (future agents)          │
│  ├── aurora       │     │                               │
│  └── atlas        │     │                               │
└───────────────────┘     └───────────────────────────────┘
```

## GitOps Pull Flow

```
1. Developer pushes to master
        │
        ▼
2. gitops-pull.timer fires on each host (every 1 min)
        │
        ▼
3. gitops-pull.sh runs:
   a. git fetch + merge --ff-only origin/master
   b. Compare OLD_COMMIT vs NEW_COMMIT
   c. If no change → exit (skip deploy)
   d. If changed → read machines/<hostname>.yaml
   e. For each container:
      - Sync flake + secrets via tar pipe
      - Push age key for sops-nix decryption
      - nixos-rebuild switch --flake /etc/nixos#<container>
   f. On failure → Discord webhook alert
        │
        ▼
4. Structured logs to systemd journal (journalctl -u gitops-pull)
   Format: level= action= host= msg= key=value
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
│   │   └── default.nix          # Shared: locale, firewall, nix settings, kernel hardening
│   └── services/
│       └── openclaw.nix         # OpenClaw systemd service module
│
├── hosts/
│   ├── _template/
│   │   └── default.nix          # Template for new agent containers
│   ├── cole/default.nix         # Cole — infrastructure agent
│   ├── aurora/default.nix       # Aurora — companion agent
│   └── atlas/default.nix        # Atlas — primary assistant
│
├── lib/
│   └── default.nix              # Shared helpers: mkAgent
│
├── secrets/
│   ├── .gitignore               # Prevents committing raw secrets
│   └── thor/
│       ├── shared.yaml          # Shared API keys (Anthropic, OpenAI, etc.)
│       ├── cole.yaml            # Cole-specific tokens
│       ├── aurora.yaml          # Aurora-specific tokens
│       └── atlas.yaml           # Atlas-specific tokens
│
├── systemd/
│   ├── gitops-pull.service      # Systemd service unit (installed on Debian hosts)
│   └── gitops-pull.timer        # Systemd timer unit (fires every 1 minute)
│
├── scripts/
│   ├── deploy.sh                # Manual deploy via incus exec (run from host)
│   ├── gitops-pull.sh           # Pull-and-deploy (called by systemd timer)
│   ├── bootstrap-host.sh        # One-time host setup script
│   └── add-container.sh         # Automated container creation helper
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

```bash
# Automated (recommended):
./scripts/add-container.sh <name>

# Manual:
1. Copy hosts/_template/ → hosts/<name>/
2. Set hostName in the new config
3. Add nixosConfigurations.<name> entry to flake.nix
4. Add to machines/<host>.yaml container list
5. incus launch images:nixos/25.11 <name> on the host
6. First deploy: ./scripts/deploy.sh <name>
7. All future deploys: automatic via timer
```

### Day-to-Day Changes

```bash
# Edit config
vim hosts/cole/default.nix

# Push — hosts deploy automatically within 1 minute
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

## Secrets Management

Secrets use [sops-nix](https://github.com/Mic92/sops-nix) with age encryption.
Each host has its own age key at `/root/.config/sops/age/keys.txt`.
Public keys are registered in `.sops.yaml`.

```bash
# Generate key (one-time per host)
age-keygen -o /root/.config/sops/age/keys.txt

# Edit secrets (auto-decrypts, re-encrypts on save)
sops secrets/thor/shared.yaml

# Decrypt to verify
sops --decrypt secrets/thor/shared.yaml
```

## Network

| Host   | IP         | Role                          |
|--------|------------|-------------------------------|
| thor   | 10.100.0.1 | Incus bridge gateway          |
| loki   | TBD        | ZimaBoard, future Incus host  |
| cole   | DHCP       | NixOS container (agent)       |
| aurora | DHCP       | NixOS container (agent)       |
| atlas  | DHCP       | NixOS container (agent)       |

## Roadmap

- [x] Wire up sops-nix for secrets in containers
- [x] Add failure alerting (Discord webhook on deploy failure)
- [ ] Configure static container IPs and update network table
- [ ] Set up loki when ZimaBoard is provisioned
- [ ] Container snapshot strategy for backups
