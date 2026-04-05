{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "mira"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false;
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.shared_vast_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "vast_api_key"; };
  sops.secrets.shared_peer_gateway_token = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "peer_gateway_token"; };
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "openrouter_api_key"; };
  sops.secrets.xai_api_key         = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "xai_api_key"; };
  sops.secrets.tavily_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "tavily_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18004" "https://10.100.0.1" "https://10.100.0.1:18004" ];
    gateway.bind = "lan";
    tools.sessionsVisibility = "all";
    tools.agentToAgent = true;
    gateway.httpToolsAllow = [ "sessions_send" "sessions_spawn" ];
    webSearch.provider = "tavily";
    webSearch.tavily.enable = true;
    messages.debounceMs = 500;  # faster followup during pipeline work
    userName = "Marc";
    maxConcurrent = 5;
    subagentsMaxConcurrent = 10;
    subagentModel = "openrouter/anthropic/claude-haiku-4-5";
    primaryModel = "openrouter/anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "openrouter/x-ai/grok-4.20"
    ];
    availableModels = [
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      "openrouter/anthropic/claude-sonnet-4-6"
      "openrouter/anthropic/claude-haiku-4-5"
      "google/gemini-2.5-pro"
      "google/gemini-2.5-flash"
      "google/imagen-4"
      "openrouter/x-ai/grok-4.20"
      "openrouter/x-ai/grok-4.20-multi-agent"
      "openrouter/x-ai/grok-4.1-fast"
      "openrouter/x-ai/grok-4-fast"
      "openrouter/x-ai/grok-4"
      "openrouter/mistralai/mistral-large-2411"
      "openrouter/mistralai/mistral-small-2603"
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/meta-llama/llama-4-scout"
      # Image generation models
      "x-ai/grok-imagine-image"
      "openrouter/google/gemini-2.5-flash-image"
      "openrouter/google/gemini-3-pro-image-preview"
      "openrouter/google/gemini-3.1-flash-image-preview"
    ];
    modelAliases = {
      "anthropic/claude-sonnet-4-6"             = "sonnet";
      "anthropic/claude-opus-4-6"              = "opus";
      "anthropic/claude-haiku-4-5"             = "haiku";
      "openrouter/anthropic/claude-sonnet-4-6" = "or-sonnet";
      "openrouter/anthropic/claude-haiku-4-5"  = "or-haiku";
      "google/gemini-2.5-pro"                  = "gemini-pro";
      "google/gemini-2.5-flash"                = "gemini-flash";
      "google/imagen-4"                        = "imagen";
      "openrouter/x-ai/grok-4.20"                   = "grok";
      "openrouter/x-ai/grok-4.20-multi-agent"     = "grok-multi";
      "openrouter/x-ai/grok-4.1-fast"             = "grok-fast";
      "openrouter/x-ai/grok-4-fast"               = "grok-4-fast";
      "openrouter/x-ai/grok-4"                    = "grok-4";
      "openrouter/mistralai/mistral-large-2411"  = "mistral-large";
      "openrouter/mistralai/mistral-small-2603" = "mistral-small";
      "openrouter/meta-llama/llama-4-maverick" = "llama-maverick";
      "openrouter/meta-llama/llama-4-scout"    = "llama-scout";
      # Image generation
      "x-ai/grok-imagine-image"                      = "grok-imagine";
      "openrouter/google/gemini-2.5-flash-image"     = "nano-banana";
      "openrouter/google/gemini-3-pro-image-preview"  = "nano-banana-pro";
      "openrouter/google/gemini-3.1-flash-image-preview" = "nano-banana-2";
    };
    customModelProviders.xai = {
      baseUrl = "https://api.x.ai/v1";
      api = "openai-responses";
      models = [
        { id = "grok-imagine-image"; name = "Grok Imagine Image"; reasoning = false; input = [ "text" "image" ]; cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; }; contextWindow = 32000; maxTokens = 4096; }
      ];
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    discord.threadBindings.enable = true;
    discord.threadBindings.spawnSubagentSessions = true;
    telegram.enable = true;
    telegram.allowFrom = [ "5201076941" ];
  };
  # Startup performance optimizations (recommended by openclaw doctor)
  systemd.services.openclaw-gateway.environment = {
    NODE_COMPILE_CACHE = "/var/tmp/openclaw-compile-cache";
    OPENCLAW_NO_RESPAWN = "1";
  };
  systemd.tmpfiles.rules = [
    "d /var/tmp/openclaw-compile-cache 0755 openclaw openclaw -"
    "d /var/lib/openclaw/workspace-backups 0750 openclaw openclaw -"
  ];

  # Workspace backup — snapshot every 5 minutes, keep last 24 snapshots (2 hours)
  systemd.services.workspace-backup = {
    description = "Backup Mira's OpenClaw workspace";
    serviceConfig = {
      Type = "oneshot";
      User = "openclaw";
      Group = "openclaw";
      ExecStart = pkgs.writeShellScript "workspace-backup" ''
        export PATH="${pkgs.git}/bin:${pkgs.openssh}/bin:${pkgs.coreutils}/bin:$PATH"
        export HOME="/var/lib/openclaw"
        WORKSPACE="/var/lib/openclaw/workspace"
        BACKUP_DIR="/var/lib/openclaw/workspace-backups"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)

        # Git commit + push
        cd "$WORKSPACE"
        if [ -d .git ]; then
          git add -A
          if ! git diff --cached --quiet 2>/dev/null; then
            git commit -m "auto: workspace snapshot $TIMESTAMP"
            git push origin main 2>/dev/null || true
          fi
        fi

        # Local snapshot
        SNAP="$BACKUP_DIR/$TIMESTAMP"
        cp -a "$WORKSPACE" "$SNAP"
        # Keep only last 24 snapshots
        ls -1dt "$BACKUP_DIR"/20* 2>/dev/null | tail -n +25 | xargs rm -rf 2>/dev/null || true
      '';
    };
  };
  systemd.timers.workspace-backup = {
    description = "Backup Mira's workspace every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      Persistent = true;
    };
  };

  environment.systemPackages = with pkgs; [ socat gh ];


  # OpenClaw GUI bridge — expose port 18790 for nginx reverse proxy on Thor
  systemd.services.openclaw-bridge = {
    description = "Bridge OpenClaw GUI to network interface";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:18790,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:18789";
      Restart = "always";
      RestartSec = "3s";
    };
  };

  networking.firewall.allowedTCPPorts = [ 18790 ];
  networking.firewall.extraInputRules = ''
    ip saddr 10.100.0.0/24 tcp dport 18789 accept
    tcp dport 18789 drop
  '';
  system.stateVersion = "25.11";
}
