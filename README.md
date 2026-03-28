# madping-cloud/infrastructure

NixOS + Incus GitOps repo for multi-host container infrastructure (Thor + Loki).

## How It Works

This repo uses a **pull-based GitOps** model:

1. Each Debian host (Thor, Loki) runs a `gitops-pull.timer` (every 5 minutes)
2. The timer runs `scripts/gitops-pull.sh`, which pulls `origin/master`
3. If there are new commits, it deploys each container listed in `machines/<hostname>.yaml`
4. Deploy: syncs the flake into the container, runs `nixos-rebuild switch` via `incus exec`

No CI runners, no push webhooks, no secrets in CI. Just a timer and git.

## Structure

```
machines/
  thor.yaml                # Containers Thor manages
  loki.yaml                # Containers Loki manages (add when provisioned)

hosts/
  _template/
    default.nix            # Template for new containers
  silas/default.nix        # silas agent container
  aurora/default.nix       # aurora agent container
  atlas/default.nix        # atlas agent container

modules/
  common/default.nix       # Shared: SSH, locale, firewall, packages
  services/openclaw.nix    # OpenClaw systemd service module

secrets/
  .gitignore
  thor/secrets.yaml        # sops-encrypted secrets for Thor containers
  loki/secrets.yaml        # sops-encrypted secrets for Loki containers

deploy/
  colmena.nix              # Colmena deployment config
  scripts/deploy.sh        # Remote deploy via nixos-rebuild --target-host

scripts/
  deploy.sh                # Manual local deploy via incus exec
  gitops-pull.sh           # Pull-and-deploy (called by systemd timer)
  bootstrap-host.sh        # One-time host setup (nix, timer, clone)

systemd/
  gitops-pull.service      # Systemd service unit
  gitops-pull.timer        # Systemd timer unit (every 5 min)

lib/default.nix            # Shared Nix helpers (mkSystem, mkContainer)
flake.nix                  # Flake: all nixosConfigurations + devShell
.sops.yaml                 # sops key routing config
```

## Bootstrapping a New Host

Run once on the Debian host:

```bash
# On the host (as root)
curl -sL https://raw.githubusercontent.com/madping-cloud/infrastructure/master/scripts/bootstrap-host.sh \
  | bash -s <hostname>

# Or if you already have the repo cloned:
./scripts/bootstrap-host.sh <hostname>
```

This will:
- Install nix (if not present)
- Install git, age, sops, jq via nix
- Clone the repo to `/opt/infrastructure`
- Set the hostname
- Guide you through age key + deploy key setup
- Install and enable `gitops-pull.timer`

## GitOps Workflow (Day-to-Day)

```bash
# 1. Edit NixOS config
vim hosts/silas/default.nix

# 2. Test build locally (optional)
nix build .#nixosConfigurations.silas.config.system.build.toplevel

# 3. Commit and push
git add -A && git commit -m "feat: describe change"
git push

# → Hosts pull within 5 minutes and deploy automatically
```

## Manual Deploy

```bash
# Deploy a single container (run from the host)
./scripts/deploy.sh silas

# Deploy all containers for this host
./scripts/deploy.sh --all

# Build only (no apply)
./scripts/deploy.sh silas --build-only

# Check timer status
systemctl status gitops-pull.timer

# Watch live deploy logs
journalctl -u gitops-pull -f

# Trigger manually
systemctl start gitops-pull
```

## Adding a Container

1. Copy template: `cp -r hosts/_template hosts/<name>`
2. Set `hostName` in `hosts/<name>/default.nix`
3. Add `nixosConfigurations` entry in `flake.nix`
4. Add container to `machines/<host>.yaml`
5. Launch on the host: `incus launch images:nixos/25.11 <name>`
6. First deploy: `./scripts/deploy.sh <name>`
7. Subsequent deploys: automatic via `gitops-pull.timer`

## Adding a New Host

1. Bootstrap the host: `./scripts/bootstrap-host.sh <hostname>`
2. Create `machines/<hostname>.yaml` with container list
3. Generate age key, add public key to `.sops.yaml`
4. Create `secrets/<hostname>/secrets.yaml` and encrypt it
5. Add GitHub deploy key (read-only) to repo settings

## Secrets Setup

Secrets are managed via [sops-nix](https://github.com/Mic92/sops-nix).

```bash
# 1. Generate an age key on the host (one-time)
age-keygen -o /root/.config/sops/age/keys.txt
# Note the public key (age1xxx...)

# 2. Add the public key to .sops.yaml, commit and push

# 3. Edit and encrypt secrets
sops secrets/thor/secrets.yaml

# 4. Decrypt to verify
sops --decrypt secrets/thor/secrets.yaml
```

## Hosts

| Hostname | IP          | Role                    | Status      |
|----------|-------------|-------------------------|-------------|
| thor     | 10.100.0.1  | Debian + Incus host     | ✅ Active    |
| loki     | TBD         | Debian + Incus (ZimaBoard) | 📋 Planned |

## Containers

| Container | Host | Role                  | Status      |
|-----------|------|-----------------------|-------------|
| silas     | thor | Executor agent        | ✅ Active    |
| aurora    | thor | Companion agent       | ✅ Active    |
| atlas     | thor | Primary assistant     | ✅ Active    |
