{ config, pkgs, lib, ... }:
let
  cfg = config.services.openclaw;
  jqBin = "${pkgs.jq}/bin/jq";

  # Build the base openclaw.json from Nix options
  # Build models attr: plain models get {}, aliased models get {alias = "...";}
  availableModelsAttr =
    (builtins.listToAttrs (map (m: { name = m; value = {}; }) cfg.availableModels))
    // (builtins.mapAttrs (model: alias: { alias = alias; }) cfg.modelAliases);

  # Build agents.list — when extraAgents are configured, we must explicitly include
  # the "main" agent in the list, otherwise agents.list replaces the implicit main.
  mainAgentEntry = {
    id = "main";
    default = true;
  };
  extraAgentEntries = lib.mapAttrsToList (id: agent: {
    inherit id;
    name = agent.name;
    model = {
      primary = agent.primaryModel;
      fallbacks = agent.fallbackModels;
    };
    workspace = agent.workspace;
  } // (lib.optionalAttrs (agent.toolsAllow != []) {
    tools.allow = agent.toolsAllow;
  }) // (lib.optionalAttrs (agent.subagentModel != null) {
    subagents.model = agent.subagentModel;
  })) cfg.extraAgents;
  agentsList = [ mainAgentEntry ] ++ extraAgentEntries;

  # Collect all bindings from extraAgents
  allBindings = lib.concatLists (lib.mapAttrsToList (_id: agent: agent.bindings) cfg.extraAgents);

  baseConfig = {
    meta = {};
    agents = {
      defaults = {
        model = {
          primary = cfg.primaryModel;
          fallbacks = cfg.fallbackModels;
        };
        models = availableModelsAttr;
        workspace = cfg.workDir;
        compaction.mode = "safeguard";
        maxConcurrent = cfg.maxConcurrent;
        subagents.maxConcurrent = cfg.subagentsMaxConcurrent;
      } // (lib.optionalAttrs (cfg.subagentModel != null) {
        subagents.model = cfg.subagentModel;
      });
    } // (lib.optionalAttrs (cfg.extraAgents != {}) { list = agentsList; });
    tools = {
      web = {
        search = { enabled = true; provider = cfg.webSearch.provider; };
        fetch.enabled = true;
      };
      sessions.visibility = cfg.tools.sessionsVisibility;
      agentToAgent.enabled = cfg.tools.agentToAgent;
    } // (if cfg.toolsAllow != [] then { allow = cfg.toolsAllow; } else {});
    messages = {
      ackReactionScope = "group-mentions";
      queue.mode = cfg.messages.queueMode;
      queue.debounceMs = cfg.messages.debounceMs;
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
      trustedProxies = [ "127.0.0.1" ];
      nodes.denyCommands = cfg.gateway.denyCommands;
    } // (lib.optionalAttrs (cfg.gateway.allowedOrigins != []) {
      controlUi.allowedOrigins = cfg.gateway.allowedOrigins;
    }) // (lib.optionalAttrs (cfg.gateway.httpToolsAllow != []) {
      tools.allow = cfg.gateway.httpToolsAllow;
    });
    plugins.entries.duckduckgo.enabled = true;
    plugins.entries.tavily.enabled = cfg.webSearch.tavily.enable;
  }
  # Add bindings when extraAgents have them
  // (lib.optionalAttrs (allBindings != []) { bindings = allBindings; });

  # Merge channels from both discord and telegram
  # When extraAgents have Discord/Telegram tokens, generate named accounts
  extraDiscordAccounts = lib.filterAttrs (_: v: v != null)
    (lib.mapAttrs (id: agent: if agent.discordTokenSecret != null then {} else null) cfg.extraAgents);
  extraTelegramAccounts = lib.filterAttrs (_: v: v != null)
    (lib.mapAttrs (id: agent: if agent.telegramTokenSecret != null then { botToken = ""; } else null) cfg.extraAgents);

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
      } // lib.optionalAttrs (extraDiscordAccounts != {}) {
        accounts = extraDiscordAccounts;
      };
    })
    // (lib.optionalAttrs cfg.telegram.enable {
      telegram = {
        enabled = true;
        dmPolicy = cfg.telegram.dmPolicy;
        groupPolicy = cfg.telegram.groupPolicy;
        streaming = cfg.telegram.streaming;
        allowFrom = cfg.telegram.allowFrom;
        groups."*".requireMention = cfg.telegram.requireMention;
        accounts = {
          default = {
            dmPolicy = "allowlist";
            groupPolicy = cfg.telegram.groupPolicy;
            streaming = cfg.telegram.streaming;
            allowFrom = cfg.telegram.allowFrom;
          };
        } // extraTelegramAccounts;
      };
    });

  fullConfig = baseConfig
    // lib.optionalAttrs (channelsAttr != {}) { channels = channelsAttr; }
    // lib.optionalAttrs (cfg.customModelProviders != {}) { models = { mode = "merge"; providers = cfg.customModelProviders; }; };
  configJson = builtins.toJSON fullConfig;

  # List of all agent IDs (main + extras) for activation scripts
  allAgentIds = [ "main" ] ++ (lib.attrNames cfg.extraAgents);
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

    # ── Concurrency options ────────────────────────────────────────────────────
    maxConcurrent = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Max concurrent conversations — gateway-wide, shared across all agents (agents.defaults.maxConcurrent)";
    };
    subagentsMaxConcurrent = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Max concurrent subagent sessions — gateway-wide, shared across all agents (agents.defaults.subagents.maxConcurrent)";
    };
    subagentModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default model for subagents spawned by the main agent (agents.defaults.subagents.model). Agents can override at spawn time.";
    };

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
    toolsAllow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra tools to allow beyond defaults for the default (main) agent. e.g. [ \"cron\" ]";
    };
    tools.sessionsVisibility = lib.mkOption {
      type = lib.types.str;
      default = "tree";
      description = "Session tool visibility: self | tree | agent | all";
    };
    tools.agentToAgent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cross-agent session targeting via tools.agentToAgent.enabled";
    };

    # ── Extra agents (multi-agent on one gateway) ─────────────────────────────
    extraAgents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; description = "Display name for this agent"; };
          primaryModel = lib.mkOption { type = lib.types.str; description = "Primary model for this agent"; };
          fallbackModels = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
          subagentModel = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Default model for subagents spawned by this agent"; };
          workspace = lib.mkOption { type = lib.types.str; description = "Workspace directory path for this agent"; };
          toolsAllow = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Tools to allow for this agent (e.g. [ \"cron\" ])"; };
          discordTokenSecret = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "sops secret name for this agent's Discord bot token"; };
          telegramTokenSecret = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "sops secret name for this agent's Telegram bot token"; };
          bindings = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; description = "Routing bindings for this agent"; };
        };
      });
      default = {};
      description = "Additional agents on this gateway. Each gets its own workspace, model config, and channel bindings.";
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
    messages.debounceMs = lib.mkOption { type = lib.types.int; default = 1000; };

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
    gateway.allowedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Allowed origins for the Control UI (gateway.controlUi.allowedOrigins).";
    };

    # ── Inter-agent comms options ──────────────────────────────────────────────────
    gateway.httpToolsAllow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Tools to allow over HTTP /tools/invoke (removes from default deny list).";
    };

    # ── Web search options ─────────────────────────────────────────────────────
    webSearch.provider = lib.mkOption { type = lib.types.str; default = "duckduckgo"; };
    webSearch.tavily.enable = lib.mkOption { type = lib.types.bool; default = false; };
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
    ] ++ (lib.concatLists (lib.mapAttrsToList (_id: agent: [
      "d ${agent.workspace}         0750 openclaw openclaw -"
      "d ${agent.workspace}/memory  0750 openclaw openclaw -"
    ]) cfg.extraAgents));

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

    # ── Extra agent directories ──────────────────────────────────────────────
    system.activationScripts.openclawAgentDirs = lib.mkIf (cfg.extraAgents != {}) { text = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: _agent: ''
        mkdir -p "/var/lib/openclaw/.openclaw/agents/${id}/agent"
        mkdir -p "/var/lib/openclaw/.openclaw/agents/${id}/sessions"
      '') cfg.extraAgents)}
      chown -R openclaw:openclaw /var/lib/openclaw/.openclaw/agents
    ''; deps = [ "openclawConfig" ]; };

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
    # Write auth-profiles.json for main agent + all extra agents
    system.activationScripts.openclawAuthPatch = { text = ''
      pick() { for v in "$@"; do [ -n "$v" ] && echo "$v" && return; done; echo ""; }

      ANTHROPIC=$(pick "$(cat /run/secrets/anthropic_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_anthropic_api_key 2>/dev/null || echo "")")
      OPENAI=$(pick "$(cat /run/secrets/openai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openai_api_key 2>/dev/null || echo "")")
      GOOGLE=$(pick "$(cat /run/secrets/google_ai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_google_ai_api_key 2>/dev/null || echo "")")
      GROQ=$(pick "$(cat /run/secrets/groq_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_groq_api_key 2>/dev/null || echo "")")
      OPENROUTER=$(pick "$(cat /run/secrets/openrouter_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_openrouter_api_key 2>/dev/null || echo "")")
      XAI=$(pick "$(cat /run/secrets/xai_api_key 2>/dev/null || echo "")" "$(cat /run/secrets/shared_xai_api_key 2>/dev/null || echo "")")

      if ! ( [ -z "$ANTHROPIC" ] && [ -z "$OPENAI" ] && [ -z "$GOOGLE" ] && [ -z "$GROQ" ] && [ -z "$OPENROUTER" ] && [ -z "$XAI" ] ); then
        # Write auth profiles for each agent (main + extras share the same API keys)
        for AGENT_ID in ${lib.concatStringsSep " " allAgentIds}; do
          AUTH_DIR="/var/lib/openclaw/.openclaw/agents/$AGENT_ID/agent"
          AUTH_FILE="$AUTH_DIR/auth-profiles.json"
          mkdir -p "$AUTH_DIR"

          TEMP=$(mktemp)
          chmod 600 "$TEMP"
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
        done
        chown -R openclaw:openclaw /var/lib/openclaw/.openclaw/agents
      fi
    ''; deps = [ "openclawConfig" "setupSecrets" ] ++ lib.optional (cfg.extraAgents != {}) "openclawAgentDirs"; };

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
        # Remove channels that OpenClaw may have persisted at runtime but are not enabled in Nix config
        ${lib.optionalString (!cfg.telegram.enable) ''
        if ${jqBin} -e '.channels.telegram' "$TEMP" >/dev/null 2>&1; then
          rm -f "$TEMP.new"
          ${jqBin} 'del(.channels.telegram)' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        ''}
        TAVILY=$(cat /run/secrets/tavily_api_key 2>/dev/null || echo "")
        if [ -n "$TAVILY" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg key "$TAVILY" '.plugins.entries.tavily.config.webSearch.apiKey = $key' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        if [ -n "$GATEWAY" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$GATEWAY" '.gateway.auth.token = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
        # Inject extra agent channel tokens
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: agent:
          (lib.optionalString (agent.discordTokenSecret != null) ''
        EA_DISCORD_${lib.toUpper id}=$(cat /run/secrets/${agent.discordTokenSecret} 2>/dev/null || echo "")
        if [ -n "$EA_DISCORD_${lib.toUpper id}" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$EA_DISCORD_${lib.toUpper id}" '.channels.discord.accounts.${id}.token = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
          '')
          + (lib.optionalString (agent.telegramTokenSecret != null) ''
        EA_TELEGRAM_${lib.toUpper id}=$(cat /run/secrets/${agent.telegramTokenSecret} 2>/dev/null || echo "")
        if [ -n "$EA_TELEGRAM_${lib.toUpper id}" ]; then
          rm -f "$TEMP.new"
          ${jqBin} --arg token "$EA_TELEGRAM_${lib.toUpper id}" '.channels.telegram.accounts.${id}.botToken = $token' "$TEMP" > "$TEMP.new" && mv "$TEMP.new" "$TEMP"
        fi
          '')
        ) cfg.extraAgents)}
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
      deploy_personality() {
        local WORKDIR="$1"
        mkdir -p "$WORKDIR/memory"
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
      }
      # Deploy to main workspace
      deploy_personality "${cfg.workDir}"
      # Deploy to extra agent workspaces
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (_id: agent: ''
      deploy_personality "${agent.workspace}"
      '') cfg.extraAgents)}
      chown -R openclaw:openclaw /var/lib/openclaw 2>/dev/null || true
    ''; deps = []; };

    # ── Systemd service ──────────────────────────────────────────────────────
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway"; after = [ "network.target" ]; wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.toJSON baseConfig) ];
      environment = { HOME = "/var/lib/openclaw"; NODE_ENV = "production"; OPENCLAW_WORKSPACE = cfg.workDir; NPM_CONFIG_PREFIX = "/var/lib/openclaw/.npm-global"; };
      serviceConfig = {
        Type = "simple"; User = "openclaw"; Group = "openclaw"; WorkingDirectory = "/var/lib/openclaw";
        Environment = [ "PATH=${pkgs.nodejs_22}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:/run/current-system/sw/bin" "NPM_CONFIG_PREFIX=/var/lib/openclaw/.npm-global" ];
        ExecStartPre = let
          ver = cfg.version;
          pkg = if ver == "latest" then "openclaw" else "openclaw@${ver}";
          delExprs = (lib.optional (!cfg.discord.enable) ".channels.discord")
            ++ (lib.optional (!cfg.telegram.enable) ".channels.telegram");
          jqDel = lib.concatStringsSep ", " delExprs;
          channelCleanup = if delExprs == [] then "" else ''
            CONFIG="/var/lib/openclaw/.openclaw/openclaw.json"
            if [ -f "$CONFIG" ]; then
              ${jqBin} 'del(${jqDel})' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
            fi
          '';
        in pkgs.writeShellScript "openclaw-prestart" ''
          NPM_BIN="/var/lib/openclaw/.npm-global/bin/openclaw"
          if [ ! -f "$NPM_BIN" ]; then
            echo "OpenClaw not found — installing ${pkg} via npm..."
            npm install -g ${pkg}
            echo "OpenClaw installed successfully"
          else
            echo "OpenClaw found at $NPM_BIN"
          fi
          ${channelCleanup}
        '';
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.execPath} gateway";
        Restart = "always"; RestartSec = "5s"; StandardOutput = "journal"; StandardError = "journal"; SyslogIdentifier = "openclaw-gateway";
      } // lib.optionalAttrs (cfg.secretsFile != null) { EnvironmentFile = cfg.secretsFile; };
    };
  };
}
