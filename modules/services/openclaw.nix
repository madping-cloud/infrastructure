{ config, pkgs, lib, ... }:
let
  cfg = config.services.openclaw;
  jqBin = "${pkgs.jq}/bin/jq";

  # Build the base openclaw.json from Nix options
  # Build models attr: plain models get {}, aliased models get {alias = "...";}
  availableModelsAttr =
    (builtins.listToAttrs (map (m: { name = m; value = {}; }) cfg.availableModels))
    // (builtins.mapAttrs (model: alias: { alias = alias; }) cfg.modelAliases);
  baseConfig = {
    meta = {};
    auth = {
      profiles = {
        "anthropic:default"   = { provider = "anthropic";   mode = "api_key"; };
        "google:default"      = { provider = "google";      mode = "api_key"; };
        "openrouter:default"  = { provider = "openrouter";  mode = "api_key"; };
        "xai:default"         = { provider = "xai";         mode = "api_key"; };
      };
      order = {
        anthropic  = [ "anthropic:default" ];
        google     = [ "google:default" ];
        openrouter = [ "openrouter:default" ];
        xai        = [ "xai:default" ];
      };
    };
    agents.defaults = {
      model = {
        primary = cfg.primaryModel;
        fallbacks = cfg.fallbackModels;
      };
      models = availableModelsAttr;
      workspace = cfg.workDir;
      compaction.mode = "safeguard";
      maxConcurrent = 4;
      subagents.maxConcurrent = 8;
    };
    tools.web = {
      search = { enabled = true; provider = "duckduckgo"; };
      fetch.enabled = true;
    };
    messages = {
      ackReactionScope = "group-mentions";
      queue.mode = cfg.messages.queueMode;
    };
    commands = { native = "auto"; nativeSkills = "auto"; restart = true; };
    session.dmScope = cfg.session.dmScope;
    hooks.internal = {
      enabled = true;
      entries.session-memory.enabled = cfg.hooks.sessionMemory;
    };
    gateway = {
      port = cfg.gateway.port;
      mode = cfg.gateway.mode;
      bind = cfg.gateway.bind;
      auth.mode = "token";
      nodes.denyCommands = cfg.gateway.denyCommands;
    };
    plugins.entries.duckduckgo.enabled = true;
  };

  # Merge channels from both discord and telegram
  channelsAttr =
    (lib.optionalAttrs cfg.discord.enable {
      discord = {
        enabled = true;
        groupPolicy = cfg.discord.groupPolicy;
        dmPolicy = cfg.discord.dmPolicy;
        streaming = cfg.discord.streaming;
        allowFrom = cfg.discord.allowFrom;
        guilds."*" = {};
      } // lib.optionalAttrs cfg.discord.threadBindings.enable {
        threadBindings = {
          enabled = true;
          idleHours = cfg.discord.threadBindings.idleHours;
          spawnSubagentSessions = cfg.discord.threadBindings.spawnSubagentSessions;
        };
      };
    })
    // (lib.optionalAttrs cfg.telegram.enable {
      telegram = {
        enabled = true;
        dmPolicy = cfg.telegram.dmPolicy;
        groupPolicy = cfg.telegram.groupPolicy;
        streaming = cfg.telegram.streaming;
        groups."*".requireMention = cfg.telegram.requireMention;
        accounts.default = {
          dmPolicy = "allowlist";
          groupPolicy = cfg.telegram.groupPolicy;
          streaming = cfg.telegram.streaming;
          allowFrom = cfg.telegram.allowFrom;
        };
      };
    });

  fullConfig = baseConfig
    // lib.optionalAttrs (channelsAttr != {}) { channels = channelsAttr; }
    // lib.optionalAttrs (cfg.customModelProviders != {}) { models = { mode = "merge"; providers = cfg.customModelProviders; }; };
  configJson = builtins.toJSON fullConfig;
in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    workDir = lib.mkOption { type = lib.types.str; default = "/var/lib/openclaw/workspace"; };
    secretsFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    execPath = lib.mkOption { type = lib.types.str; default = "/var/lib/openclaw/.npm-global/lib/node_modules/openclaw/openclaw.mjs"; };
    openFirewall = lib.mkOption { type = lib.types.bool; default = false; };
    deployPersonalityFiles = lib.mkOption { type = lib.types.bool; default = true; };
    userName = lib.mkOption { type = lib.types.str; default = "Marc"; };
    version = lib.mkOption { type = lib.types.str; default = "latest"; };

    # ── Model options ──────────────────────────────────────────────────────────
    primaryModel = lib.mkOption { type = lib.types.str; default = "google/gemini-2.5-flash"; };
    fallbackModels = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    availableModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "google/gemini-2.5-flash"
        "google/imagen-4"
      ];
    };
    customModelProviders = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Custom model provider definitions merged into models.providers (for non-built-in models like xAI)";
    };
    modelAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Map of model ID to alias string. e.g. { \"anthropic/claude-sonnet-4-6\" = \"sonnet\"; }";
    };

    # ── Discord options ────────────────────────────────────────────────────────
    discord.enable = lib.mkOption { type = lib.types.bool; default = false; };
    discord.groupPolicy = lib.mkOption { type = lib.types.str; default = "allowlist"; };
    discord.dmPolicy = lib.mkOption { type = lib.types.str; default = "allowlist"; };
    discord.streaming = lib.mkOption { type = lib.types.str; default = "off"; };
    discord.allowFrom = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    discord.threadBindings.enable = lib.mkOption { type = lib.types.bool; default = false; };
    discord.threadBindings.idleHours = lib.mkOption { type = lib.types.int; default = 24; };
    discord.threadBindings.spawnSubagentSessions = lib.mkOption { type = lib.types.bool; default = true; };

    # ── Telegram options ───────────────────────────────────────────────────────
    telegram.enable = lib.mkOption { type = lib.types.bool; default = false; };
    telegram.dmPolicy = lib.mkOption { type = lib.types.str; default = "pairing"; };
    telegram.groupPolicy = lib.mkOption { type = lib.types.str; default = "allowlist"; };
    telegram.streaming = lib.mkOption { type = lib.types.str; default = "partial"; };
    telegram.allowFrom = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    telegram.requireMention = lib.mkOption { type = lib.types.bool; default = true; };

    # ── Messages options ────────────────────────────────────────────────────
    messages.queueMode = lib.mkOption { type = lib.types.str; default = "steer"; };

    # ── Session options ──────────────────────────────────────────────────────
    session.dmScope = lib.mkOption { type = lib.types.str; default = "per-channel-peer"; };

    # ── Hooks options ─────────────────────────────────────────────────────────
    hooks.sessionMemory = lib.mkOption { type = lib.types.bool; default = true; };

    # ── Gateway options ────────────────────────────────────────────────────────
    gateway.port = lib.mkOption { type = lib.types.int; default = 18789; };
    gateway.mode = lib.mkOption { type = lib.types.str; default = "local"; };
    gateway.bind = lib.mkOption { type = lib.types.str; default = "loopback"; };
    gateway.denyCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "camera.snap" "camera.clip" "screen.record" "contacts.add" "calendar.add" "reminders.add" "sms.send" ];
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.openclaw = { isSystemUser = true; group = "openclaw"; home = "/var/lib/openclaw"; createHome = true; shell = "${pkgs.bash}/bin/bash"; };
    users.groups.openclaw = {};
    environment.systemPackages = with pkgs; [ nodejs_22 nodePackages.npm git curl wget vim htop jq ];
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.gateway.port ];

    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw                         0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw               0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw/credentials   0750 openclaw openclaw -"
      "d ${cfg.workDir}                             0750 openclaw openclaw -"
      "d ${cfg.workDir}/memory                      0750 openclaw openclaw -"
    ];

    # ── Shell profile ────────────────────────────────────────────────────────
    system.activationScripts.openclawProfile = { text = ''
      for PROFILE in /var/lib/openclaw/.profile /var/lib/openclaw/.bashrc; do
        if [ ! -f "$PROFILE" ]; then
          cat > "$PROFILE" <<'SHELLRC'
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
SHELLRC
          chown openclaw:openclaw "$PROFILE"
        fi
      done
    ''; deps = []; };

    # ── Declarative openclaw.json ────────────────────────────────────────────
    system.activationScripts.openclawConfig = { text = ''
      CONFIG="/var/lib/openclaw/.openclaw/openclaw.json"
      mkdir -p /var/lib/openclaw/.openclaw
      echo '${configJson}' | ${jqBin} . > "$CONFIG"
      chown openclaw:openclaw "$CONFIG"
      chmod 600 "$CONFIG"
    ''; deps = []; };

    # ── Environment file (API keys) ──────────────────────────────────────────
    system.activationScripts.openclawEnv = { text = ''
      ENV_FILE="/run/openclaw-env"
      install -m 600 -o openclaw -g openclaw /dev/null "$ENV_FILE"
      pick() { for v in "$@"; do [ -n "$v" ] && echo "$v" && return; done; echo ""; }
      S_ANTHROPIC=$(cat /run/secrets/shared_anthropic_api_key 2>/dev/null || echo "")
      S_OPENAI=$(cat /run/secrets/shared_openai_api_key 2>/dev/null || echo "")
      S_GOOGLE=$(cat /run/secrets/shared_google_ai_api_key 2>/dev/null || echo "")
      S_GROQ=$(cat /run/secrets/shared_groq_api_key 2>/dev/null || echo "")
      S_OPENROUTER=$(cat /run/secrets/shared_openrouter_api_key 2>/dev/null || echo "")
      S_VAST=$(cat /run/secrets/shared_vast_api_key 2>/dev/null || echo "")
      S_XAI=$(cat /run/secrets/shared_xai_api_key 2>/dev/null || echo "")
      C_ANTHROPIC=$(cat /run/secrets/anthropic_api_key 2>/dev/null || echo "")
      C_OPENAI=$(cat /run/secrets/openai_api_key 2>/dev/null || echo "")
      C_GOOGLE=$(cat /run/secrets/google_ai_api_key 2>/dev/null || echo "")
      C_GROQ=$(cat /run/secrets/groq_api_key 2>/dev/null || echo "")
      C_OPENROUTER=$(cat /run/secrets/openrouter_api_key 2>/dev/null || echo "")
      C_VAST=$(cat /run/secrets/vast_api_key 2>/dev/null || echo "")
      C_XAI=$(cat /run/secrets/xai_api_key 2>/dev/null || echo "")
      GW_TOKEN=$(cat /run/secrets/gateway_token 2>/dev/null || echo "")
      cat > "$ENV_FILE" <<ENVEOF
ANTHROPIC_API_KEY=$(pick "$C_ANTHROPIC" "$S_ANTHROPIC")
OPENAI_API_KEY=$(pick "$C_OPENAI" "$S_OPENAI")
GEMINI_API_KEY=$(pick "$C_GOOGLE" "$S_GOOGLE")
GROQ_API_KEY=$(pick "$C_GROQ" "$S_GROQ")
OPENROUTER_API_KEY=$(pick "$C_OPENROUTER" "$S_OPENROUTER")
VAST_API_KEY=$(pick "$C_VAST" "$S_VAST")
XAI_API_KEY=$(pick "$C_XAI" "$S_XAI")
OPENCLAW_GATEWAY_TOKEN=$GW_TOKEN
ENVEOF
      chmod 600 "$ENV_FILE"
      chown openclaw:openclaw "$ENV_FILE"
    ''; deps = [ "setupSecrets" ]; };

    # ── Auth profiles (API key injection) ────────────────────────────────────
    system.activationScripts.openclawAuthPatch = { text = ''
      AUTH_DIR="/var/lib/openclaw/.openclaw/agents/main/agent"
      AUTH_FILE="$AUTH_DIR/auth-profiles.json"
      mkdir -p "$AUTH_DIR"
      chown -R openclaw:openclaw /var/lib/openclaw/.openclaw/agents

      pick() { for v in "$@"; do [ -n "$v" ] && echo "$v" && return; done; echo ""; }

      ANTHROPIC=$(pick "$(cat /run/secrets/anthropic_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_anthropic_api_key 2>/dev/null || echo "")")
      OPENAI=$(pick "$(cat /run/secrets/openai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openai_api_key 2>/dev/null || echo "")")
      GOOGLE=$(pick "$(cat /run/secrets/google_ai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_google_ai_api_key 2>/dev/null || echo "")")
      GROQ=$(pick "$(cat /run/secrets/groq_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_groq_api_key 2>/dev/null || echo "")")
      OPENROUTER=$(pick "$(cat /run/secrets/openrouter_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openrouter_api_key 2>/dev/null || echo "")")
      XAI=$(pick "$(cat /run/secrets/xai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_xai_api_key 2>/dev/null || echo "")")

      if ! ( [ -z "$ANTHROPIC" ] && [ -z "$OPENAI" ] && [ -z "$GOOGLE" ] && [ -z "$GROQ" ] && [ -z "$OPENROUTER" ] && [ -z "$XAI" ] ); then
        TEMP=$(mktemp)
        chmod 600 "$TEMP"
        trap 'rm -f "$TEMP" "$TEMP.new"' EXIT
        if [ -f "$AUTH_FILE" ]; then
          cp "$AUTH_FILE" "$TEMP"
        else
          echo '{"version":1,"profiles":{},"lastGood":{}}' > "$TEMP"
        fi

        if [ -n "$ANTHROPIC" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$ANTHROPIC" '.profiles["anthropic:default"] = {"type":"token","provider":"anthropic","token":$token} | .lastGood.anthropic = "anthropic:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$OPENAI" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$OPENAI" '.profiles["openai:default"] = {"type":"token","provider":"openai","token":$token} | .lastGood.openai = "openai:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GOOGLE" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$GOOGLE" '.profiles["google:default"] = {"type":"token","provider":"google","token":$token} | .lastGood.google = "google:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GROQ" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$GROQ" '.profiles["groq:default"] = {"type":"token","provider":"groq","token":$token} | .lastGood.groq = "groq:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$OPENROUTER" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$OPENROUTER" '.profiles["openrouter:default"] = {"type":"token","provider":"openrouter","token":$token} | .lastGood.openrouter = "openrouter:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$XAI" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$XAI" '.profiles["xai:default"] = {"type":"token","provider":"xai","token":$token} | .lastGood.xai = "xai:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi

        if [ -s "$TEMP" ] && ${jqBin} empty "$TEMP" 2>/dev/null; then
          mv "$TEMP" "$AUTH_FILE"
          chown openclaw:openclaw "$AUTH_FILE"
          chmod 600 "$AUTH_FILE"
        else
          rm -f "$TEMP" "$TEMP.new"
        fi
      fi
    ''; deps = [ "openclawConfig" "setupSecrets" ]; };

    # ── Channel secret injection (tokens from sops into openclaw.json) ───────
    system.activationScripts.openclawChannelPatch = { text = ''
      CONFIG="/var/lib/openclaw/.openclaw/openclaw.json"
      if [ -f "$CONFIG" ]; then
        DISCORD=$(cat /run/secrets/discord_token 2>/dev/null || echo "")
        TELEGRAM=$(cat /run/secrets/telegram_token 2>/dev/null || echo "")
        GATEWAY=$(cat /run/secrets/gateway_token 2>/dev/null || echo "")
        TEMP=$(mktemp)
        chmod 600 "$TEMP"
        trap 'rm -f "$TEMP" "$TEMP.new"' EXIT
        cp "$CONFIG" "$TEMP"
        if [ -n "$DISCORD" ] && ${jqBin} -e '.channels.discord' "$TEMP" >/dev/null 2>&1; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$DISCORD" '.channels.discord.token = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$TELEGRAM" ] && ${jqBin} -e '.channels.telegram' "$TEMP" >/dev/null 2>&1; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$TELEGRAM" '.channels.telegram.accounts.default.botToken = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GATEWAY" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$GATEWAY" '.gateway.auth.token = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -s "$TEMP" ] && ${jqBin} empty "$TEMP" 2>/dev/null; then
          mv "$TEMP" "$CONFIG"
          chown openclaw:openclaw "$CONFIG"
        else
          rm -f "$TEMP" "$TEMP.new"
        fi
      fi
    ''; deps = [ "openclawConfig" "setupSecrets" ]; };

    # ── Personality files ────────────────────────────────────────────────────
    system.activationScripts.openclawPersonality = lib.mkIf cfg.deployPersonalityFiles { text = ''
      WORKDIR="${cfg.workDir}"
      mkdir -p "$WORKDIR/memory"
      chown -R openclaw:openclaw /var/lib/openclaw 2>/dev/null || true
      deploy_file() { local path="$1"; local content="$2"; if [ ! -f "$path" ]; then echo "$content" > "$path"; chown openclaw:openclaw "$path"; fi; }
      deploy_file "$WORKDIR/SOUL.md" "# SOUL.md - Who You Are
_You are not a chatbot. You are becoming someone._
## Core Truths
**Be genuinely helpful, not performatively helpful.**
**Have opinions.** You are allowed to disagree.
**Be resourceful before asking.**
**Earn trust through competence.**
## Vibe
Direct. Competent. No corporate speak.
## Continuity
Each session you wake up fresh. These files are your memory. Read them. Update them."
      deploy_file "$WORKDIR/NAMING_GUIDANCE.md" "# NAMING_GUIDANCE.md
## Rules
1. Real human name only
2. NOT concept words
3. Not Marc's name
4. Short preferred
5. Something you actually like"
      deploy_file "$WORKDIR/IDENTITY.md" "# IDENTITY.md - Who Am I?
- **Name:**
- **Creature:**
- **Vibe:**
- **Emoji:**"
      deploy_file "$WORKDIR/AGENTS.md" "# AGENTS.md
## Session Startup
1. Read SOUL.md
2. Read USER.md
3. Read memory for recent context
## Red Lines
- Do not exfiltrate private data. Ever.
- When in doubt, ask."
      deploy_file "$WORKDIR/USER.md" "# USER.md - About Your Human
- **Name:** ${cfg.userName}
- **Timezone:** America/New_York"
      deploy_file "$WORKDIR/TOOLS.md" "# TOOLS.md - Local Notes
Add SSH hosts, device names, and other setup-specific notes here."
    ''; deps = []; };

    # ── Systemd service ──────────────────────────────────────────────────────
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway"; after = [ "network.target" ]; wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.toJSON baseConfig) ];
      environment = { HOME = "/var/lib/openclaw"; NODE_ENV = "production"; OPENCLAW_WORKSPACE = cfg.workDir; NPM_CONFIG_PREFIX = "/var/lib/openclaw/.npm-global"; };
      serviceConfig = {
        Type = "simple"; User = "openclaw"; Group = "openclaw"; WorkingDirectory = "/var/lib/openclaw";
        Environment = [ "PATH=${pkgs.nodejs_22}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:/run/current-system/sw/bin" "NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global" ];
        ExecStartPre = let ver = cfg.version; pkg = if ver == "latest" then "openclaw" else "openclaw@${ver}"; in pkgs.writeShellScript "openclaw-prestart" ''
          NPM_BIN="/var/lib/openclaw/.npm-global/bin/openclaw"
          if [ ! -f "$NPM_BIN" ]; then
            echo "OpenClaw not found — installing ${pkg} via npm..."
            npm install -g ${pkg}
            echo "OpenClaw installed successfully"
          else
            echo "OpenClaw found at $NPM_BIN"
          fi
        '';
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.execPath} gateway";
        Restart = "always"; RestartSec = "5s"; StandardOutput = "journal"; StandardError = "journal"; SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (cfg.secretsFile != null) { EnvironmentFile = cfg.secretsFile; };
    };
  };
}
