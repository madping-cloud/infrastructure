# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Pull-based GitOps infrastructure for NixOS containers on Debian hosts using Incus. Commits to `master` auto-deploy within ~1 minute via a systemd timer — no CI runners or webhooks.

## Architecture

**Hosts** (Debian + Incus): Thor (10.100.0.1), Loki (planned)
**Containers** (NixOS 25.11 on Thor):

| Container | Agent(s) | Role | Primary Model | Auth | Tier |
|-----------|----------|------|---------------|------|------|
| atlas | Atlas + Morgan | COO + Monitoring Lead (two agents, one gateway) | sonnet-4-6 / haiku-4-5 | Max sub | 1 — sessions_spawn + cron |
| cole | Cole | Infrastructure Lead — all infra, VMs, networking, deploys | sonnet-4-6 | Max sub | 1 — sessions_spawn |
| mira | Mira | Writing Team Lead — adult naturism/nudism fiction (16 subagents) | sonnet-4-6 | Anthropic API | 1 — sessions_spawn + cron |
| aurora | Aurora | Companion — Connie's chatbot | gemini-flash | Google AI | 3 — non-Anthropic |

**Multi-agent on atlas:** Morgan runs as an `extraAgent` on Atlas's gateway, with separate workspace (`/var/lib/openclaw/workspace-morgan`), own Discord/Telegram bots, and channel routing bindings. This enables native agent-to-agent communication (`sessions_send`, `sessions_spawn`) between Atlas and Morgan without cross-gateway federation (which OpenClaw does not support).

Every container's NixOS config is built from a module stack applied by `lib/default.nix`'s `mkAgent` helper:
1. `sops-nix` — secret decryption
2. `modules/common/default.nix` — base config (locale, firewall, packages, kernel hardening)
3. `modules/services/openclaw.nix` — OpenClaw AI agent service (core module)
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
# Manual deploy (run on Thor as root)
./scripts/deploy.sh cole              # single container
./scripts/deploy.sh --all             # all containers on this host
./scripts/deploy.sh cole --build-only # dry run

# Deploy via SSH from local machine
ssh root@192.168.4.6 'cd /opt/infrastructure && git pull --ff-only && ./scripts/deploy.sh --all'

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

# Push personality files to a container
./scripts/provision-agent.sh <name>

# Enter dev shell (installs git, sops, age, jq, nixos-rebuild + pre-commit hook)
nix develop
```

## Inter-Agent Communication

**Same-gateway agents (Atlas ↔ Morgan):** Atlas and Morgan share a gateway on the `atlas` container. They communicate natively via `sessions_send` and `sessions_spawn` — no network calls needed. Channel routing uses `bindings[]` with `accountId` matching to direct Discord/Telegram messages to the correct agent.

**Cross-gateway agents (Atlas/Morgan ↔ Cole):** Cole runs on a separate gateway. OpenClaw has **no cross-gateway federation** — the peer roster (`/run/openclaw-peers.json`) is dead code. Cross-gateway communication is not currently possible. If needed in the future, it would require an OpenClaw feature addition or an external bridge.

**Required gateway config for agent-to-agent comms (same gateway):**
- `tools.agentToAgent = true` — enable cross-agent targeting
- `tools.sessionsVisibility = "all"` — see all sessions
- `gateway.httpToolsAllow = [ "sessions_send" "sessions_spawn" ]` — allow session tools

Each lead agent manages a team of subagents:
- **Atlas (COO)**: VP Content, VP Marketing, Script Writer, Research Analyst, Creative Director, Production Coord, Finance Analyst
- **Cole (Infra Lead)**: DevOps Engineer, Network Engineer, VM Provisioner, Automation Engineer
- **Morgan (Monitoring)**: Threat Analyst, Alert Dispatcher, Uptime Monitor drones, Log Analyzer drones, Infra Health drones
- **Mira (Writing Lead)**: Nova (Ideation), Aria (Story Architect), Lena (Character Designer), Sable (Research), Iris (World Builder), Lyra (Series Planner), Cass (Dialogue), Reid (Scene Choreographer), Thea (Prose Editor), Freya (Continuity), Orin (Developmental Editor), Sage (Sensitivity Reviewer), Remy (Beta Reader), Dex (Content Ratings), Cal (Publishing Strategist), Elise (Publishing Prep), Sloane (Marketing Strategist)

Persistent subagents are resumed via `sessions_send`. On-demand subagents are spawned fresh. Morgan's drone subagents run on cron schedules using cheap OpenRouter models (Llama-Scout, Gemini-Flash-Lite).

**Model policy:** No Chinese-origin models (DeepSeek, Qwen). Approved: Anthropic, Google, xAI (Cole only), Meta/Mistral/Inception via OpenRouter.

## Secrets

Managed via sops-nix with age encryption. Key routing in `.sops.yaml`.

- **Shared keys**: `secrets/<hostname>/shared.yaml` (API keys shared across containers)
- **Per-container**: `secrets/<hostname>/<container>.yaml` (tokens, per-container API key overrides)
- **Age key** (on host): `/root/.config/sops/age/keys.txt`

Per-container keys override shared keys when both exist. The `openclaw.nix` module injects decrypted secrets into `openclaw.json`, `auth-profiles.json`, and `/run/openclaw-env` at deploy time.

A pre-commit hook (auto-installed by `nix develop`) blocks committing unencrypted secrets.

## Personalities

Agent personality files (SOUL.md, IDENTITY.md, AGENTS.md, USER.md, TOOLS.md) live in a separate repo: `github.com/madping-cloud/personalities`. Structure: `agents/<name>/{SOUL,IDENTITY,AGENTS,USER,TOOLS}.md`. Push via `scripts/provision-agent.sh` or manually.

## Known Issues

**OpenClaw crash loop on rate limit:** When Anthropic rate limits hit, OpenClaw's "live session model switch" pins the session to the failing model, overriding all fallback attempts — creating an infinite retry loop. **Recovery:** Stop gateway, clear sessions (`rm -f /var/lib/openclaw/sessions/*.jsonl`), restart gateway. **Prevention:** Keep concurrency low, use haiku as first fallback (not opus), include non-Anthropic models in fallback chain.

## Key Conventions

- All deploys are **fast-forward only** — keep master linear
- SSH is disabled in containers; use `incus exec <container> -- <command>`
- Nix sandbox is disabled (LXC incompatibility)
- OpenClaw config is fully declarative via `services.openclaw.*` options in host configs — the module regenerates `openclaw.json` from scratch on every deploy
- Structured logging format: `level= action= host= msg= key=value`
- Atlas and Morgan share the `atlas` container (multi-agent gateway); Cole has its own container
- Atlas, Cole, and Morgan run on Claude Max subscription; Mira uses Anthropic API; Aurora uses Google AI
- Atlas has NO root access to Thor — Cole handles all infrastructure changes
- Morgan owns ALL scheduled monitoring (cron) — security + infra health consolidated under one agent
- Mira leads a 17-member writing team for adult fiction; subagents use Anthropic models by specialty: opus (Orin, Sage), sonnet (Nova, Aria, Lena, Cass, Thea, Iris, Lyra), haiku (Freya, Reid, Dex, Sable, Remy, Elise, Sloane, Cal); pipelines: ideation → research/world-build → plot/characters → drafting → edit/dialogue/continuity → sensitivity/beta/ratings → publishing/marketing
- Multi-agent config uses `extraAgents` option in `openclaw.nix` — per-agent model, workspace, tools, and channel bindings; `maxConcurrent` and `availableModels` are gateway-wide (not per-agent)
