# madping-cloud/infrastructure

NixOS + Incus GitOps repo for multi-host container infrastructure (Thor + Loki).

## How It Works

This repo uses a **pull-based GitOps** model:

1. Each Debian host (Thor, Loki) runs a `gitops-pull.timer` (every 1 minute)
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
  cole/default.nix         # cole agent container
  aurora/default.nix       # aurora agent container
  atlas/default.nix        # atlas agent container

modules/
  common/default.nix       # Shared: SSH, locale, firewall, packages
  services/openclaw.nix    # OpenClaw systemd service module

secrets/
  .gitignore
  thor/
    shared.yaml            # sops-encrypted shared API keys for Thor containers
    cole.yaml              # sops-encrypted cole-specific secrets
    aurora.yaml            # sops-encrypted aurora-specific secrets
    atlas.yaml             # sops-encrypted atlas-specific secrets
  loki/                    # sops-encrypted secrets for Loki containers

scripts/
  deploy.sh                # Manual local deploy via incus exec
  gitops-pull.sh           # Pull-and-deploy (called by systemd timer)
  bootstrap-host.sh        # One-time host setup (nix, timer, clone)
  add-container.sh         # Automated container creation helper

systemd/
  gitops-pull.service      # Systemd service unit
  gitops-pull.timer        # Systemd timer unit (every 1 min)

lib/default.nix            # Shared Nix helpers (mkAgent)
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
vim hosts/cole/default.nix

# 2. Test build locally (optional)
nix build .#nixosConfigurations.cole.config.system.build.toplevel

# 3. Commit and push
git add -A && git commit -m "feat: describe change"
git push

# → Hosts pull within 1 minute and deploy automatically
```

## Manual Deploy

```bash
# Deploy a single container (run from the host)
./scripts/deploy.sh cole

# Deploy all containers for this host
./scripts/deploy.sh --all

# Build only (no apply)
./scripts/deploy.sh cole --build-only

# Check timer status
systemctl status gitops-pull.timer

# Watch live deploy logs
journalctl -u gitops-pull -f

# Trigger manually
systemctl start gitops-pull
```

## Adding a Container

```bash
# Automated (recommended):
./scripts/add-container.sh <name>

# Manual:
1. Copy template: cp -r hosts/_template hosts/<name>
2. Set hostName in hosts/<name>/default.nix
3. Add nixosConfigurations entry in flake.nix
4. Add container to machines/<host>.yaml
5. Launch on the host: incus launch images:nixos/25.11 <name>
6. First deploy: ./scripts/deploy.sh <name>
7. Subsequent deploys: automatic via gitops-pull.timer
```

## OpenClaw Module Options

Each agent's behavior is configured declaratively via `services.openclaw.*` in its host config (`hosts/<name>/default.nix`). The module writes a fresh `openclaw.json` on every deploy — secrets (tokens, API keys) are injected on top from sops.

### Minimal config (new agent)

```nix
services.openclaw = {
  enable = true;
  openFirewall = true;
  secretsFile = "/run/openclaw-env";
};
```

This gives you: Gemini Flash as primary model, Imagen 4 available, no channels, gateway on port 18789.

### Full options reference

**Core:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable OpenClaw service |
| `openFirewall` | bool | `false` | Open gateway + web ports |
| `secretsFile` | string | `null` | Path to env file with API keys |
| `userName` | string | `"Marc"` | Human name for personality files |
| `version` | string | `"latest"` | npm package version to pin |
| `deployPersonalityFiles` | bool | `true` | Deploy SOUL.md, USER.md, etc. |
| `workDir` | string | `"/var/lib/openclaw/workspace"` | Agent workspace path |

**Models:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `primaryModel` | string | `"google/gemini-2.5-flash"` | Primary AI model |
| `fallbackModels` | list of strings | `[]` | Fallback models in order |
| `availableModels` | list of strings | `["google/gemini-2.5-flash" "google/imagen-4"]` | All models the agent can use |

**Discord:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `discord.enable` | bool | `false` | Enable Discord channel |
| `discord.groupPolicy` | string | `"allowlist"` | `"open"` or `"allowlist"` |
| `discord.dmPolicy` | string | `"allowlist"` | DM access policy |
| `discord.streaming` | string | `"off"` | Message streaming mode |
| `discord.allowFrom` | list of strings | `[]` | Allowed Discord user IDs |
| `discord.threadBindings.enable` | bool | `false` | Enable thread bindings |
| `discord.threadBindings.idleHours` | int | `24` | Thread idle timeout |
| `discord.threadBindings.spawnSubagentSessions` | bool | `true` | Spawn subagent per thread |

**Telegram:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `telegram.enable` | bool | `false` | Enable Telegram channel |
| `telegram.dmPolicy` | string | `"allowlist"` | DM access policy |
| `telegram.groupPolicy` | string | `"allowlist"` | Group access policy |
| `telegram.streaming` | string | `"partial"` | Message streaming mode |
| `telegram.allowFrom` | list of strings | `[]` | Allowed Telegram user IDs |
| `telegram.requireMention` | bool | `true` | Require @mention in groups |

**Gateway:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gateway.port` | int | `18789` | Gateway listen port |
| `gateway.mode` | string | `"local"` | Gateway mode |
| `gateway.bind` | string | `"loopback"` | Bind address |
| `gateway.denyCommands` | list of strings | *(safe defaults)* | Commands to deny from nodes |

### Examples

**Cole** — Anthropic-first with Discord:
```nix
services.openclaw = {
  enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
  primaryModel = "anthropic/claude-sonnet-4-6";
  fallbackModels = [ "anthropic/claude-opus-4-6" "anthropic/claude-haiku-4-5" "google/gemini-2.5-flash" ];
  availableModels = [ "google/gemini-2.5-flash" "google/imagen-4" "anthropic/claude-opus-4-6" "anthropic/claude-sonnet-4-6" "anthropic/claude-haiku-4-5" ];
  discord.enable = true;
  discord.groupPolicy = "open";
};
```

**Atlas** — Gemini-first with Discord + Telegram:
```nix
services.openclaw = {
  enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
  discord.enable = true;
  discord.allowFrom = [ "166609345080066048" ];
  discord.threadBindings.enable = true;
  telegram.enable = true;
  telegram.allowFrom = [ "5201076941" ];
};
```

**Aurora** — Gemini-only with Telegram:
```nix
services.openclaw = {
  enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
  userName = "Connie";
  telegram.enable = true;
  telegram.allowFrom = [ "8580758213" "5201076941" ];
};
```

### Secrets

Bot tokens and API keys are **not** in the Nix config — they live in sops-encrypted `secrets/thor/<name>.yaml` files and get injected at deploy time:

| Secret key | Injected into |
|------------|---------------|
| `discord_token` | `channels.discord.token` in openclaw.json |
| `telegram_token` | `channels.telegram.botToken` in openclaw.json |
| `gateway_token` | `gateway.auth.token` in openclaw.json |
| `anthropic_api_key` | auth-profiles.json + env file |
| `google_ai_api_key` | auth-profiles.json + env file |
| `openai_api_key` | auth-profiles.json + env file |
| `groq_api_key` | auth-profiles.json + env file |
| `openrouter_api_key` | auth-profiles.json + env file |

Per-container keys override shared keys (`shared.yaml`) when both exist.

## Adding a New Host

1. Bootstrap the host: `./scripts/bootstrap-host.sh <hostname>`
2. Create `machines/<hostname>.yaml` with container list
3. Generate age key, add public key to `.sops.yaml`
4. Create `secrets/<hostname>/shared.yaml` and per-container secrets, encrypt them
5. Add GitHub deploy key (read-only) to repo settings

## Secrets Setup

Secrets are managed via [sops-nix](https://github.com/Mic92/sops-nix).

```bash
# 1. Generate an age key on the host (one-time)
age-keygen -o /root/.config/sops/age/keys.txt
# Note the public key (age1xxx...)

# 2. Add the public key to .sops.yaml, commit and push

# 3. Edit and encrypt secrets
sops secrets/thor/shared.yaml

# 4. Decrypt to verify
sops --decrypt secrets/thor/shared.yaml
```

## Hosts

| Hostname | IP          | Role                    | Status      |
|----------|-------------|-------------------------|-------------|
| thor     | 10.100.0.1  | Debian + Incus host     | Active      |
| loki     | TBD         | Debian + Incus (ZimaBoard) | Planned  |

## Containers

| Container | Host | Role                              | Status      |
|-----------|------|-----------------------------------|-------------|
| cole      | thor | Infrastructure agent              | Active      |
| atlas     | thor | Primary assistant                 | Active      |
| aurora    | thor | Companion agent                   | Planned     |
