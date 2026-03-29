{ config, pkgs, lib, ... }:
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    workDir = lib.mkOption { type = lib.types.str; default = "/var/lib/openclaw/workspace"; };
    secretsFile = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    execPath = lib.mkOption { type = lib.types.str; default = "/var/lib/openclaw/.npm-global/lib/node_modules/openclaw/openclaw.mjs"; };
    openFirewall = lib.mkOption { type = lib.types.bool; default = false; };
    deployPersonalityFiles = lib.mkOption { type = lib.types.bool; default = true; };
    userName = lib.mkOption { type = lib.types.str; default = "Marc"; description = "Human user name for personality files"; };
    version = lib.mkOption { type = lib.types.str; default = "latest"; description = "OpenClaw npm version to install (e.g. '1.2.3' or 'latest')"; };
    primaryModel = lib.mkOption { type = lib.types.str; default = "google/gemini-2.5-flash"; description = "Primary AI model for this agent"; };
    fallbackModels = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Fallback models (empty = no fallbacks)"; };
  };

  config = lib.mkIf config.services.openclaw.enable {
    users.users.openclaw = { isSystemUser = true; group = "openclaw"; home = "/var/lib/openclaw"; createHome = true; shell = "${pkgs.bash}/bin/bash"; };
    users.groups.openclaw = {};
    environment.systemPackages = with pkgs; [ nodejs_22 nodePackages.npm git curl wget vim htop jq ];
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.openclaw.openFirewall [ 8080 18789 ];

    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw                         0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw               0750 openclaw openclaw -"
      "d /var/lib/openclaw/.openclaw/credentials   0750 openclaw openclaw -"
      "d ${config.services.openclaw.workDir}        0750 openclaw openclaw -"
      "d ${config.services.openclaw.workDir}/memory 0750 openclaw openclaw -"
    ];

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

    system.activationScripts.openclawConfig = { text = let
      jq = "${pkgs.jq}/bin/jq";
      primary = config.services.openclaw.primaryModel;
      fallbacks = builtins.toJSON config.services.openclaw.fallbackModels;
    in ''
      CONFIG="/var/lib/openclaw/.openclaw/openclaw.json"
      if [ ! -f "$CONFIG" ]; then
        mkdir -p /var/lib/openclaw/.openclaw
        cat > "$CONFIG" << 'CONFIGJSON'
{"meta":{},"auth":{"profiles":{"anthropic:default":{"provider":"anthropic","mode":"api_key"},"google:default":{"provider":"google","mode":"api_key"}},"order":{"anthropic":["anthropic:default"],"google":["google:default"]}},"agents":{"defaults":{"model":{"primary":"google/gemini-2.5-flash","fallbacks":[]},"models":{"anthropic/claude-opus-4-6":{},"anthropic/claude-sonnet-4-6":{},"anthropic/claude-haiku-4-5":{},"google/gemini-2.5-flash":{},"google/imagen-4":{}},"workspace":"/var/lib/openclaw/workspace","compaction":{"mode":"safeguard"},"maxConcurrent":4,"subagents":{"maxConcurrent":8}}},"tools":{"web":{"search":{"enabled":true,"provider":"duckduckgo"},"fetch":{"enabled":true}}},"messages":{"ackReactionScope":"group-mentions"},"commands":{"native":"auto","nativeSkills":"auto","restart":true},"gateway":{"port":18789,"mode":"local","bind":"loopback","auth":{"mode":"token"}},"plugins":{"entries":{"duckduckgo":{"enabled":true}}}}
CONFIGJSON
        ${jq} --arg primary '${primary}' --argjson fallbacks '${fallbacks}' \
          '.agents.defaults.model.primary = $primary | .agents.defaults.model.fallbacks = $fallbacks' \
          "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
        chown openclaw:openclaw "$CONFIG"
      fi
    ''; deps = []; };

    system.activationScripts.openclawEnv = { text = ''
      ENV_FILE="/run/openclaw-env"
      pick() { for v in "$@"; do [ -n "$v" ] && echo "$v" && return; done; echo ""; }
      S_ANTHROPIC=$(cat /run/secrets/shared_anthropic_api_key 2>/dev/null || echo "")
      S_OPENAI=$(cat /run/secrets/shared_openai_api_key 2>/dev/null || echo "")
      S_GOOGLE=$(cat /run/secrets/shared_google_ai_api_key 2>/dev/null || echo "")
      S_GROQ=$(cat /run/secrets/shared_groq_api_key 2>/dev/null || echo "")
      S_OPENROUTER=$(cat /run/secrets/shared_openrouter_api_key 2>/dev/null || echo "")
      C_ANTHROPIC=$(cat /run/secrets/anthropic_api_key 2>/dev/null || echo "")
      C_OPENAI=$(cat /run/secrets/openai_api_key 2>/dev/null || echo "")
      C_GOOGLE=$(cat /run/secrets/google_ai_api_key 2>/dev/null || echo "")
      C_GROQ=$(cat /run/secrets/groq_api_key 2>/dev/null || echo "")
      C_OPENROUTER=$(cat /run/secrets/openrouter_api_key 2>/dev/null || echo "")
      cat > "$ENV_FILE" <<ENVEOF
ANTHROPIC_API_KEY=$(pick "$C_ANTHROPIC" "$S_ANTHROPIC")
OPENAI_API_KEY=$(pick "$C_OPENAI" "$S_OPENAI")
GOOGLE_AI_API_KEY=$(pick "$C_GOOGLE" "$S_GOOGLE")
GROQ_API_KEY=$(pick "$C_GROQ" "$S_GROQ")
OPENROUTER_API_KEY=$(pick "$C_OPENROUTER" "$S_OPENROUTER")
ENVEOF
      chmod 600 "$ENV_FILE"
      chown openclaw:openclaw "$ENV_FILE"
    ''; deps = [ "setupSecrets" ]; };

    system.activationScripts.openclawAuthPatch = { text = let jq = "${pkgs.jq}/bin/jq"; in ''
      AUTH_DIR="/var/lib/openclaw/.openclaw/agents/main/agent"
      AUTH_FILE="$AUTH_DIR/auth-profiles.json"
      mkdir -p "$AUTH_DIR"

      pick() { for v in "$@"; do [ -n "$v" ] && echo "$v" && return; done; echo ""; }

      ANTHROPIC=$(pick "$(cat /run/secrets/anthropic_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_anthropic_api_key 2>/dev/null || echo "")")
      OPENAI=$(pick "$(cat /run/secrets/openai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openai_api_key 2>/dev/null || echo "")")
      GOOGLE=$(pick "$(cat /run/secrets/google_ai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_google_ai_api_key 2>/dev/null || echo "")")
      GROQ=$(pick "$(cat /run/secrets/groq_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_groq_api_key 2>/dev/null || echo "")")
      OPENROUTER=$(pick "$(cat /run/secrets/openrouter_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openrouter_api_key 2>/dev/null || echo "")")

      if ! ( [ -z "$ANTHROPIC" ] && [ -z "$OPENAI" ] && [ -z "$GOOGLE" ] && [ -z "$GROQ" ] && [ -z "$OPENROUTER" ] ); then
        if [ -f "$AUTH_FILE" ]; then
          TEMP=$(mktemp)
          cp "$AUTH_FILE" "$TEMP"
        else
          TEMP=$(mktemp)
          echo '{"version":1,"profiles":{},"lastGood":{}}' > "$TEMP"
        fi

        if [ -n "$ANTHROPIC" ]; then
          rm -f "$TEMP.new"
          ${jq} --arg token "$ANTHROPIC" '.profiles["anthropic:default"] = {"type":"token","provider":"anthropic","token":$token} | .lastGood.anthropic = "anthropic:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$OPENAI" ]; then
          rm -f "$TEMP.new"
          ${jq} --arg token "$OPENAI" '.profiles["openai:default"] = {"type":"token","provider":"openai","token":$token} | .lastGood.openai = "openai:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GOOGLE" ]; then
          rm -f "$TEMP.new"
          ${jq} --arg token "$GOOGLE" '.profiles["google:default"] = {"type":"token","provider":"google","token":$token} | .lastGood.google = "google:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GROQ" ]; then
          rm -f "$TEMP.new"
          ${jq} --arg token "$GROQ" '.profiles["groq:default"] = {"type":"token","provider":"groq","token":$token} | .lastGood.groq = "groq:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$OPENROUTER" ]; then
          rm -f "$TEMP.new"
          ${jq} --arg token "$OPENROUTER" '.profiles["openrouter:default"] = {"type":"token","provider":"openrouter","token":$token} | .lastGood.openrouter = "openrouter:default"' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi

        if [ -s "$TEMP" ] && ${jq} empty "$TEMP" 2>/dev/null; then
          mv "$TEMP" "$AUTH_FILE"
          chown openclaw:openclaw "$AUTH_FILE"
          chmod 600 "$AUTH_FILE"
        else
          rm -f "$TEMP" "$TEMP.new"
        fi
      fi
    ''; deps = [ "openclawConfig" "setupSecrets" ]; };

    system.activationScripts.openclawChannelPatch = { text = let jq = "${pkgs.jq}/bin/jq"; in ''
      CONFIG="/var/lib/openclaw/.openclaw/openclaw.json"
      if [ -f "$CONFIG" ]; then
        DISCORD=$(cat /run/secrets/discord_token 2>/dev/null || echo "")
        TELEGRAM=$(cat /run/secrets/telegram_token 2>/dev/null || echo "")
        GATEWAY=$(cat /run/secrets/gateway_token 2>/dev/null || echo "")
        TEMP=$(mktemp)
        cp "$CONFIG" "$TEMP"
        if [ -n "$DISCORD" ]; then
          ${jq} --arg token "$DISCORD" '.channels.discord = (.channels.discord // {}) | .channels.discord.enabled = true | .channels.discord.token = $token | .channels.discord.groupPolicy = (.channels.discord.groupPolicy // "open") | .channels.discord.streaming = (.channels.discord.streaming // "off")' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$TELEGRAM" ]; then
          ${jq} --arg token "$TELEGRAM" '.channels.telegram = (.channels.telegram // {}) | .channels.telegram.enabled = true | .channels.telegram.botToken = $token | .channels.telegram.dmPolicy = (.channels.telegram.dmPolicy // "allowlist") | .channels.telegram.groupPolicy = (.channels.telegram.groupPolicy // "allowlist") | .channels.telegram.streaming = (.channels.telegram.streaming // "partial")' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GATEWAY" ]; then
          ${jq} --arg token "$GATEWAY" '.gateway.auth.token = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -s "$TEMP" ] && ${jq} empty "$TEMP" 2>/dev/null; then
          mv "$TEMP" "$CONFIG"
          chown openclaw:openclaw "$CONFIG"
        else
          rm -f "$TEMP" "$TEMP.new"
        fi
      fi
    ''; deps = [ "openclawConfig" "setupSecrets" ]; };

    system.activationScripts.openclawPersonality = lib.mkIf config.services.openclaw.deployPersonalityFiles { text = ''
      WORKDIR="${config.services.openclaw.workDir}"
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
3. Not Marc s name
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
- **Name:** ${config.services.openclaw.userName}
- **Timezone:** America/New_York"
      deploy_file "$WORKDIR/TOOLS.md" "# TOOLS.md - Local Notes
Add SSH hosts, device names, and other setup-specific notes here."
    ''; deps = []; };

    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway"; after = [ "network.target" ]; wantedBy = [ "multi-user.target" ];
      environment = { HOME = "/var/lib/openclaw"; NODE_ENV = "production"; OPENCLAW_WORKSPACE = config.services.openclaw.workDir; NPM_CONFIG_PREFIX = "/var/lib/openclaw/.npm-global"; };
      serviceConfig = {
        Type = "simple"; User = "openclaw"; Group = "openclaw"; WorkingDirectory = "/var/lib/openclaw";
        Environment = [ "PATH=${pkgs.nodejs_22}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:/run/current-system/sw/bin" "NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global" ];
        ExecStartPre = let ver = config.services.openclaw.version; pkg = if ver == "latest" then "openclaw" else "openclaw@${ver}"; in pkgs.writeShellScript "openclaw-prestart" ''
          NPM_BIN="/var/lib/openclaw/.npm-global/bin/openclaw"
          if [ ! -f "$NPM_BIN" ]; then
            echo "OpenClaw not found — installing ${pkg} via npm..."
            npm install -g ${pkg}
            echo "OpenClaw installed successfully"
          else
            echo "OpenClaw found at $NPM_BIN"
          fi
        '';
        ExecStart = "${pkgs.nodejs_22}/bin/node ${config.services.openclaw.execPath} gateway";
        Restart = "on-failure"; RestartSec = "30s"; StandardOutput = "journal"; StandardError = "journal"; SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (config.services.openclaw.secretsFile != null) { EnvironmentFile = config.services.openclaw.secretsFile; };
    };
  };
}
