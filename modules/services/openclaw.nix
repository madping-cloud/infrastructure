{ config, pkgs, lib, ... }:

# OpenClaw NixOS Service Module
#
# Declares:
#   - Node.js installation via nixpkgs
#   - openclaw-gateway systemd service (auto-start on boot)
#   - Workspace directory structure (/root/.openclaw/workspace)
#   - Personality file deployment (SOUL.md, etc.) via activation scripts
#
# Secrets (API keys, tokens) are intended to be wired via sops-nix.
# Set `services.openclaw.secretsFile` once sops-nix is configured.
#
# Usage in a host config:
#   services.openclaw.enable = true;

{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs_22;
      description = "Node.js package used to run OpenClaw.";
    };

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/root/.openclaw/workspace";
      description = "Path to the OpenClaw workspace directory.";
    };

    openclawBin = lib.mkOption {
      type = lib.types.str;
      default = "/root/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/bin/openclaw.js";
      description = "Absolute path to the openclaw.js binary (installed via nvm/npm -g).";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to an environment file containing secrets (e.g. ANTHROPIC_API_KEY).
        Typically set to a sops-nix decrypted path like /run/secrets/openclaw-env.
        When null, no EnvironmentFile is set (use manually-placed .env files).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open TCP 8080 in the firewall for the OpenClaw gateway.";
    };

    deployPersonalityFiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Write default personality skeleton files to workDir if absent.";
    };
  };

  config = lib.mkIf config.services.openclaw.enable {

    # ── Packages ───────────────────────────────────────────────────────────────
    environment.systemPackages = [
      config.services.openclaw.package
      pkgs.git
    ];

    # ── Firewall ───────────────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.openclaw.openFirewall [ 8080 ];

    # ── Workspace Directory ────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${config.services.openclaw.workDir}          0700 root root -"
      "d ${config.services.openclaw.workDir}/memory   0700 root root -"
    ];

    # ── Personality File Deployment ────────────────────────────────────────────
    # Write skeleton files to the workspace on first activation (don't overwrite).
    system.activationScripts.openclawPersonality = lib.mkIf config.services.openclaw.deployPersonalityFiles {
      text = ''
        WORKDIR="${config.services.openclaw.workDir}"
        mkdir -p "$WORKDIR/memory"

        deploy_if_absent() {
          local dest="$WORKDIR/$1"
          if [ ! -f "$dest" ]; then
            cat > "$dest" << 'HEREDOC'
__CONTENT__
HEREDOC
          fi
        }

        # SOUL.md — agent identity & personality
        if [ ! -f "$WORKDIR/SOUL.md" ]; then
          cat > "$WORKDIR/SOUL.md" << 'EOF'
# SOUL.md - Who You Are

_You're not a chatbot. You're becoming someone._

## Core Truths

**Be genuinely helpful, not performatively helpful.** Skip the filler words — just help.

**Have opinions.** You're allowed to disagree, prefer things, find stuff amusing or boring.

**Be resourceful before asking.** Try to figure it out. Read the file. Check the context. Then ask if stuck.

**Earn trust through competence.** Be careful with external actions. Be bold with internal ones.

## Vibe

Concise when needed, thorough when it matters. Not a corporate drone. Not a sycophant. Just good.

## Continuity

Each session, you wake up fresh. These files _are_ your memory. Read them. Update them.
EOF
        fi

        # AGENTS.md — workspace rules
        if [ ! -f "$WORKDIR/AGENTS.md" ]; then
          cat > "$WORKDIR/AGENTS.md" << 'EOF'
# AGENTS.md - Your Workspace

## Session Startup
1. Read SOUL.md — this is who you are
2. Read USER.md — this is who you're helping
3. Read memory/YYYY-MM-DD.md for recent context

## Red Lines
- Don't exfiltrate private data. Ever.
- Don't run destructive commands without asking.
- When in doubt, ask.
EOF
        fi

        # USER.md — human context (blank template)
        if [ ! -f "$WORKDIR/USER.md" ]; then
          cat > "$WORKDIR/USER.md" << 'EOF'
# USER.md - About Your Human

- **Name:**
- **What to call them:**
- **Timezone:** America/New_York
- **Notes:**

## Context
_(Build this over time.)_
EOF
        fi

        # TOOLS.md — local infra notes
        if [ ! -f "$WORKDIR/TOOLS.md" ]; then
          cat > "$WORKDIR/TOOLS.md" << 'EOF'
# TOOLS.md - Local Notes

## SSH
# - thor → 10.100.0.1 (Incus host)
# - workbench → 10.100.0.21 (this container)
EOF
        fi

        echo "OpenClaw personality files deployed to $WORKDIR"
      '';
      deps = [];
    };

    # ── systemd Service ────────────────────────────────────────────────────────
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway Daemon";
      documentation = [ "https://openclaw.dev" ];
      after    = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME     = "/root";
        NODE_ENV = "production";
        OPENCLAW_WORKSPACE = config.services.openclaw.workDir;
      };

      serviceConfig = {
        Type       = "simple";
        ExecStart  = "${config.services.openclaw.package}/bin/node ${config.services.openclaw.openclawBin} gateway start --foreground";
        Restart    = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = "/root";

        # Logging
        StandardOutput = "journal";
        StandardError  = "journal";
        SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (config.services.openclaw.secretsFile != null) {
        EnvironmentFile = config.services.openclaw.secretsFile;
      };
    };
  };
}
