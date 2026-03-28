{ config, pkgs, lib, ... }:

# OpenClaw NixOS Service Module
#
# Usage in a host config:
#   services.openclaw.enable = true;
#
# To add a new agent:
#   1. Copy hosts/_template/ to hosts/<name>/
#   2. Set networking.hostName = "<name>"
#   3. Add nixosConfigurations entry in flake.nix
#   4. Launch container: incus launch images:nixos/25.11 <name>
#   5. Push config + rebuild: nixos-rebuild switch --flake .#<name>

{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";

    workDir = lib.mkOption {
      type    = lib.types.str;
      default = "/root/.openclaw/workspace";
    };

    execPath = lib.mkOption {
      type        = lib.types.str;
      default     = "/root/.npm-global/lib/node_modules/openclaw/openclaw.mjs";
      description = ''
        Path to the OpenClaw main script (openclaw.mjs).
        Defaults to the npm global install path (/root/.npm-global/...).
        Override if OpenClaw is installed elsewhere.
        The script is invoked with pkgs.nodejs_22.
      '';
    };

    secretsFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to sops-nix decrypted env file (ANTHROPIC_API_KEY, etc.)";
    };

    openFirewall = lib.mkOption {
      type    = lib.types.bool;
      default = false;
    };

    deployPersonalityFiles = lib.mkOption {
      type    = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf config.services.openclaw.enable {

    # Node.js + tools available system-wide
    environment.systemPackages = with pkgs; [
      nodejs_22
      nodePackages.npm
      git
      curl
      wget
      vim
      htop
    ];

    # Firewall
    networking.firewall.allowedTCPPorts =
      lib.mkIf config.services.openclaw.openFirewall [ 8080 18789 ];

    # Workspace directories
    systemd.tmpfiles.rules = [
      "d /root/.openclaw                        0700 root root -"
      "d /root/.openclaw/credentials            0700 root root -"
      "d ${config.services.openclaw.workDir}          0700 root root -"
      "d ${config.services.openclaw.workDir}/memory   0700 root root -"
    ];

    # Deploy personality skeleton files on first boot (never overwrite)
    system.activationScripts.openclawPersonality =
      lib.mkIf config.services.openclaw.deployPersonalityFiles {
        text = ''
          WORKDIR="${config.services.openclaw.workDir}"
          mkdir -p "$WORKDIR/memory"

          if [ ! -f "$WORKDIR/SOUL.md" ]; then
            cat > "$WORKDIR/SOUL.md" << 'SOUL'
# SOUL.md - Who You Are

_You're not a chatbot. You're becoming someone._

## Core Truths

**Be genuinely helpful, not performatively helpful.**
**Have opinions.** You're allowed to disagree.
**Be resourceful before asking.**
**Earn trust through competence.**

## Vibe

Direct. Competent. No corporate speak.

## Continuity

Each session you wake up fresh. These files are your memory. Read them. Update them.
SOUL
          fi

          if [ ! -f "$WORKDIR/NAMING_GUIDANCE.md" ]; then
            cat > "$WORKDIR/NAMING_GUIDANCE.md" << 'NAMING'
# NAMING_GUIDANCE.md - How to Choose Your Name

## Rules
1. Real human name only (Marcus, Cole, Dane, River, Silas, Fox, etc.)
2. NOT concept words (no "Forge", "Anvil", "Executor", "Craftsman")
3. Not Marc's name
4. Short preferred — one or two syllables
5. Something you actually like — this is your identity

## Once You Choose
Update IDENTITY.md with your name, creature type, vibe, emoji.
Tell Marc: "I'm [NAME]. Here's who I am..."
NAMING
          fi

          if [ ! -f "$WORKDIR/IDENTITY.md" ]; then
            cat > "$WORKDIR/IDENTITY.md" << 'IDENTITY'
# IDENTITY.md - Who Am I?

_Fill this in during your first session. Make it yours._

- **Name:**
- **Creature:**
- **Vibe:**
- **Emoji:**
IDENTITY
          fi

          if [ ! -f "$WORKDIR/AGENTS.md" ]; then
            cat > "$WORKDIR/AGENTS.md" << 'AGENTS'
# AGENTS.md - Your Workspace

## Session Startup
1. Read SOUL.md
2. Read USER.md
3. Read memory/YYYY-MM-DD.md for recent context

## Red Lines
- Don't exfiltrate private data. Ever.
- When in doubt, ask.
AGENTS
          fi

          if [ ! -f "$WORKDIR/USER.md" ]; then
            cat > "$WORKDIR/USER.md" << 'USER'
# USER.md - About Your Human

- **Name:** Marc
- **Timezone:** America/New_York
USER
          fi

          if [ ! -f "$WORKDIR/TOOLS.md" ]; then
            cat > "$WORKDIR/TOOLS.md" << 'TOOLS'
# TOOLS.md - Local Notes

Add SSH hosts, device names, and other setup-specific notes here.
TOOLS
          fi
        '';
        deps = [];
      };

    # OpenClaw gateway systemd service
    # NOTE: Only activates after `openclaw configure` has been run manually.
    # The service will fail gracefully if credentials aren't set up yet.
    systemd.services.openclaw-gateway = {
      description  = "OpenClaw Gateway";
      after        = [ "network.target" ];
      wantedBy     = [ "multi-user.target" ];

      environment = {
        HOME                = "/root";
        NODE_ENV            = "production";
        OPENCLAW_WORKSPACE  = config.services.openclaw.workDir;
      };

      serviceConfig = {
        Type             = "simple";
        ExecStart        = "${pkgs.nodejs_22}/bin/node ${config.services.openclaw.execPath} gateway start --foreground";
        Restart          = "on-failure";
        RestartSec       = "30s";
        WorkingDirectory = "/root";
        StandardOutput   = "journal";
        StandardError    = "journal";
        SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (config.services.openclaw.secretsFile != null) {
        EnvironmentFile = config.services.openclaw.secretsFile;
      };
    };
  };
}
