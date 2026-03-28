{ config, pkgs, lib, ... }:

# OpenClaw NixOS Service Module
#
# Runs OpenClaw as a dedicated non-root system user (openclaw).
# The service user has no sudo, no login shell, and is isolated to its home dir.
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
#   6. Install OpenClaw: su - openclaw -c "npm install -g openclaw"
#   7. Configure: su - openclaw -c "openclaw configure"

{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";

    workDir = lib.mkOption {
      type    = lib.types.str;
      default = "/var/lib/openclaw/workspace";
      description = "OpenClaw workspace directory (owned by openclaw user).";
    };

    secretsFile = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to sops-nix decrypted env file (ANTHROPIC_API_KEY, etc.)";
    };

    execPath = lib.mkOption {
      type    = lib.types.str;
      default = "/var/lib/openclaw/.npm-global/lib/node_modules/openclaw/openclaw.mjs";
      description = "Path to openclaw.mjs (npm global install path for the openclaw user).";
    };

    openFirewall = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Open ports 8080 and 18789 for OpenClaw gateway.";
    };

    deployPersonalityFiles = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Deploy SOUL.md, NAMING_GUIDANCE.md, etc. on first boot.";
    };
  };

  config = lib.mkIf config.services.openclaw.enable {

    # ── Dedicated openclaw user ───────────────────────────────────────────────
    users.users.openclaw = {
      isSystemUser   = true;
      group          = "openclaw";
      home           = "/var/lib/openclaw";
      createHome     = true;
      shell          = "${pkgs.bash}/bin/bash";
      description    = "OpenClaw AI assistant service user";
    };
    users.groups.openclaw = {};

    # ── Node.js available system-wide for npm install ─────────────────────────
    environment.systemPackages = with pkgs; [
      nodejs_22
      nodePackages.npm
      git
      curl
      wget
      vim
      htop
    ];

    # ── Firewall ──────────────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts =
      lib.mkIf config.services.openclaw.openFirewall [ 8080 18789 ];

    # ── Workspace directories ─────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw                             0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw                   0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw/credentials       0750 openclaw openclaw -"
      "d ${config.services.openclaw.workDir}            0750 openclaw openclaw -"
      "d ${config.services.openclaw.workDir}/memory     0750 openclaw openclaw -"
    ];

    # ── Shell profile for interactive `su - openclaw` sessions ────────────────
    system.activationScripts.openclawProfile = {
      text = ''
        for PROFILE in /var/lib/openclaw/.profile /var/lib/openclaw/.bashrc; do
          if [ ! -f "$PROFILE" ]; then
            cat > "$PROFILE" <<'SHELLRC'
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
SHELLRC
            chown openclaw:openclaw "$PROFILE"
          fi
        done
      '';
      deps = [];
    };

    # ── Personality files (deployed once, never overwritten) ──────────────────
    system.activationScripts.openclawPersonality =
      lib.mkIf config.services.openclaw.deployPersonalityFiles {
        text = ''
          WORKDIR="${config.services.openclaw.workDir}"
          mkdir -p "$WORKDIR/memory"
          chown -R openclaw:openclaw /var/lib/openclaw 2>/dev/null || true

          deploy_file() {
            local path="$1"
            local content="$2"
            if [ ! -f "$path" ]; then
              echo "$content" > "$path"
              chown openclaw:openclaw "$path"
            fi
          }

          deploy_file "$WORKDIR/SOUL.md" '# SOUL.md - Who You Are

_You'"'"'re not a chatbot. You'"'"'re becoming someone._

## Core Truths

**Be genuinely helpful, not performatively helpful.**
**Have opinions.** You'"'"'re allowed to disagree.
**Be resourceful before asking.**
**Earn trust through competence.**

## Vibe

Direct. Competent. No corporate speak.

## Continuity

Each session you wake up fresh. These files are your memory. Read them. Update them.'

          deploy_file "$WORKDIR/NAMING_GUIDANCE.md" '# NAMING_GUIDANCE.md - How to Choose Your Name

## Rules
1. Real human name only (Marcus, Cole, Dane, River, Silas, Fox, etc.)
2. NOT concept words (no "Forge", "Anvil", "Executor", "Craftsman")
3. Not Marc'"'"'s name
4. Short preferred — one or two syllables
5. Something you actually like — this is your identity

## Once You Choose
Update IDENTITY.md with your name, creature type, vibe, emoji.
Tell Marc: "I'"'"'m [NAME]. Here'"'"'s who I am..."'

          deploy_file "$WORKDIR/IDENTITY.md" '# IDENTITY.md - Who Am I?

_Fill this in during your first session. Make it yours._

- **Name:**
- **Creature:**
- **Vibe:**
- **Emoji:**'

          deploy_file "$WORKDIR/AGENTS.md" '# AGENTS.md - Your Workspace

## Session Startup
1. Read SOUL.md
2. Read USER.md
3. Read memory/YYYY-MM-DD.md for recent context

## Red Lines
- Don'"'"'t exfiltrate private data. Ever.
- When in doubt, ask.'

          deploy_file "$WORKDIR/USER.md" '# USER.md - About Your Human

- **Name:** Marc
- **Timezone:** America/New_York'

          deploy_file "$WORKDIR/TOOLS.md" '# TOOLS.md - Local Notes

Add SSH hosts, device names, and other setup-specific notes here.'
        '';
        deps = [];
      };

    # ── OpenClaw gateway systemd service ──────────────────────────────────────
    systemd.services.openclaw-gateway = {
      description  = "OpenClaw Gateway";
      after        = [ "network.target" ];
      wantedBy     = [ "multi-user.target" ];

      environment = {
        HOME                = "/var/lib/openclaw";
        NODE_ENV            = "production";
        OPENCLAW_WORKSPACE  = config.services.openclaw.workDir;
        NPM_CONFIG_PREFIX   = "/var/lib/openclaw/.npm-global";
      };

      serviceConfig = {
        Type             = "simple";
        User             = "openclaw";
        Group            = "openclaw";
        WorkingDirectory = "/var/lib/openclaw";

        # Full PATH so npm postinstall scripts (e.g. sharp) can find sh, cc, etc.
        Environment = [
          "PATH=${pkgs.nodejs_22}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:/run/current-system/sw/bin"
          "NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global"
        ];

        # Verify openclaw binary exists before starting
        ExecStartPre = pkgs.writeShellScript "openclaw-check" ''
          NPM_BIN="/var/lib/openclaw/.npm-global/bin/openclaw"
          if [ ! -f "$NPM_BIN" ]; then
            echo "ERROR: OpenClaw not installed. Run as root:"
            echo "  NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global npm install -g openclaw"
            echo "  chown -R openclaw:openclaw /var/lib/openclaw/.npm-global"
            exit 1
          fi
          echo "OpenClaw found at $NPM_BIN"
        '';

        ExecStart        = "${pkgs.nodejs_22}/bin/node ${config.services.openclaw.execPath} gateway start";
        Restart          = "on-failure";
        RestartSec       = "30s";
        StandardOutput   = "journal";
        StandardError    = "journal";
        SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (config.services.openclaw.secretsFile != null) {
        EnvironmentFile = config.services.openclaw.secretsFile;
      };
    };
  };
}
