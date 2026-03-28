# madping-cloud/infrastructure

NixOS + Incus GitOps repo for Thor's container infrastructure.

## Structure

```
hosts/
  thor/
    default.nix              # Thor host config (Incus host)
    containers/
      openclaw.nix           # workbench container (OpenClaw AI)
  zimaboard/
    default.nix              # Future: ZimaBoard host
  _template/
    default.nix              # Copy for new hosts

modules/
  common/
    default.nix              # Base config: SSH, locale, firewall, packages
  services/
    openclaw.nix             # OpenClaw systemd service module

secrets/
  .gitignore
  thor/
    secrets.yaml             # sops-encrypted secrets (API keys, tokens)

deploy/
  colmena.nix                # Colmena deployment config
  scripts/
    deploy.sh                # Manual deploy script

lib/
  default.nix                # Shared Nix helpers (mkSystem, mkContainer)

flake.nix                    # Flake: all nixosConfigurations + devShell
.sops.yaml                   # sops key routing config
```

## Quick Start

```bash
# Enter dev shell (provides nixos-rebuild, colmena, sops, age)
nix develop

# Validate all configurations
nix flake check

# Build workbench config (no deploy)
./deploy/scripts/deploy.sh workbench --build-only

# Deploy to workbench container
./deploy/scripts/deploy.sh workbench

# Dry-run (show what would change)
./deploy/scripts/deploy.sh workbench --dry-run
```

## Secrets Setup

Secrets are managed via [sops-nix](https://github.com/Mic92/sops-nix).

```bash
# 1. Generate an age key on Thor
age-keygen -o /root/.config/sops/age/keys.txt
# Save the public key!

# 2. Update .sops.yaml with the public key

# 3. Edit and encrypt secrets
sops secrets/thor/secrets.yaml

# 4. Uncomment sops-nix in flake.nix and wire up modules
```

## Hosts

| Hostname    | IP           | Role                         | Status   |
|-------------|--------------|------------------------------|----------|
| workbench   | 10.100.0.21  | OpenClaw AI assistant        | ✅ Active |
| thor        | 10.100.0.1   | Incus host                   | 🔧 Planned |
| zimaboard   | TBD          | Future host                  | 📋 Template |

## Adding a New Host

1. Copy `hosts/_template/default.nix` to `hosts/<name>/default.nix`
2. Fill in hostname, networking, services
3. Add to `flake.nix` nixosConfigurations
4. Add to `deploy/colmena.nix`
5. Add to `deploy/scripts/deploy.sh` HOST_IPS map
