# Infrastructure Architecture

## Overview

Thor (Debian host) runs Incus containers. NixOS containers are configured declaratively via this GitOps repo.

## Stack

```
Thor (Debian host)
└── Incus
    └── workbench (NixOS 25.11 container)
        ├── OpenClaw gateway daemon
        └── Future services...
```

## Directory Structure

```
infrastructure/
├── flake.nix                    # Entry point — pins nixpkgs, defines hosts
├── flake.lock                   # Pinned dependency hashes
├── nixos/
│   ├── modules/
│   │   ├── common.nix           # Shared: locale, SSH, nix settings
│   │   ├── openclaw.nix         # OpenClaw service module
│   │   └── hardening.nix        # Firewall, kernel params, audit
│   └── hosts/
│       └── workbench/
│           └── configuration.nix  # workbench-specific config
├── secrets/
│   ├── .gitignore               # Prevents committing raw secrets
│   └── secrets.yaml             # sops-encrypted secrets (template)
├── scripts/
│   ├── bootstrap.sh             # One-time container setup
│   └── deploy.sh                # Day-to-day deploy
└── docs/
    └── ARCHITECTURE.md          # This file
```

## Workflow

### Initial Setup (once per container)
```bash
./scripts/bootstrap.sh workbench
```

### Day-to-day Changes
1. Edit NixOS modules in `nixos/`
2. Test build: `./scripts/deploy.sh workbench --build-only`
3. Apply: `./scripts/deploy.sh workbench`
4. Commit: `git add -A && git commit -m "feat: describe change"`

### Secrets Management
Secrets use [sops-nix](https://github.com/Mic92/sops-nix) with age encryption.

```bash
# Generate age key (one-time)
age-keygen -o /root/.config/sops/age/keys.txt

# Configure .sops.yaml with your age public key
# Encrypt secrets
sops --encrypt --in-place secrets/secrets.yaml
```

## Network

| Host      | IP           | Role           |
|-----------|--------------|----------------|
| Thor      | 10.100.0.1   | Incus bridge   |
| workbench | 10.100.0.21  | NixOS container|

## Day 2 Plans

- [ ] Configure sops-nix for secrets management
- [ ] Wire up OpenClaw service with real API keys
- [ ] Set up SSH key access into container
- [ ] Configure automatic builds on git push (Gitea Actions or similar)
- [ ] Snapshot strategy for container backups
