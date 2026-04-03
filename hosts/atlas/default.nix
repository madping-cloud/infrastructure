{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "atlas"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false; # secrets live at runtime paths not available during nix eval
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.shared_vast_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "vast_api_key"; };
  sops.secrets.shared_peer_gateway_token = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "peer_gateway_token"; };
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "openrouter_api_key"; };
  sops.secrets.tavily_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "tavily_api_key"; };
  # Morgan's channel tokens (consolidated from siem)
  sops.secrets.morgan_discord_token  = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "morgan_discord_token"; };
  sops.secrets.morgan_telegram_token = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "morgan_telegram_token"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18002" "https://10.100.0.1" "https://10.100.0.1:18002" ];
    gateway.bind = "lan";
    tools.sessionsVisibility = "all";
    tools.agentToAgent = true;
    gateway.httpToolsAllow = [ "sessions_send" "sessions_spawn" ];
    messages.debounceMs = 500;  # faster followup when steer can't inject mid-tool
    userName = "Marc";
    maxConcurrent = 5;          # gateway-wide: Atlas 3 + Morgan 2
    subagentsMaxConcurrent = 8; # shared pool for both agents
    primaryModel = "anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "anthropic/claude-haiku-4-5"
      "google/gemini-2.5-pro"
      "openai/gpt-4o"
    ];
    availableModels = [
      # Anthropic (direct — primary, on Max subscription)
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      # Google (direct — strong multimodal)
      "google/gemini-2.5-flash"
      "google/gemini-2.5-pro"
      "google/gemini-2.5-flash-lite"
      "google/imagen-4"
      # OpenAI (direct)
      "openai/gpt-4o"
      # OpenRouter — cheap capable workers
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/mistralai/mistral-small-2603"
      "openrouter/inception/mercury-2"
      "openrouter/google/gemini-2.5-flash-lite"
    ];
    modelAliases = {
      "anthropic/claude-sonnet-4-6"             = "sonnet";            # Default — best reasoning, on subscription
      "anthropic/claude-opus-4-6"               = "opus";              # Deep reasoning, hard problems
      "anthropic/claude-haiku-4-5"              = "haiku";             # Fastest Claude, mechanical tasks
      "google/gemini-2.5-flash"                 = "gemini-flash";      # Fast, multimodal, conversational
      "google/gemini-2.5-pro"                   = "gemini-pro";        # Google's best
      "google/gemini-2.5-flash-lite"            = "gemini-flash-lite"; # Lighter/cheaper Google
      "openai/gpt-4o"                           = "gpt-4o";            # OpenAI flagship
      "openrouter/meta-llama/llama-4-scout"     = "llama-scout";       # $0.08/1M — cheapest capable worker
      "openrouter/meta-llama/llama-4-maverick"  = "llama-maverick";    # $0.15/1M — 1M ctx, multi-step tasks
      "openrouter/mistralai/mistral-small-2603" = "mistral-small";     # $0.15/1M — creative/narrative
      "openrouter/inception/mercury-2"          = "mercury";           # $0.25/1M — 1000+ tok/s, text-only
      "openrouter/google/gemini-2.5-flash-lite" = "or-gemini-lite";    # OpenRouter path for Gemini lite
    };
    browser.cdpUrl = "ws://127.0.0.1:18800";
    browser.attachOnly = true;
    webSearch.provider = "tavily";
    webSearch.tavily.enable = true;
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    discord.threadBindings.enable = true;
    telegram.enable = true;
    telegram.allowFrom = [ "5201076941" ];
    # ── Morgan (Monitoring Lead) — consolidated from siem container ─────────
    extraAgents.morgan = {
      name = "Morgan";
      primaryModel = "anthropic/claude-haiku-4-5";
      fallbackModels = [
        "openrouter/meta-llama/llama-4-maverick"
        "openrouter/meta-llama/llama-4-scout"
      ];
      subagentModel = "openrouter/meta-llama/llama-4-scout";
      workspace = "/var/lib/openclaw/workspace-morgan";
      toolsAllow = [ "cron" ];
      discordTokenSecret = "morgan_discord_token";
      telegramTokenSecret = "morgan_telegram_token";
      bindings = [
        { type = "route"; agentId = "morgan"; match = { channel = "discord"; accountId = "morgan"; }; }
        { type = "route"; agentId = "morgan"; match = { channel = "telegram"; accountId = "morgan"; }; }
      ];
    };
  };
  # Startup performance optimizations (recommended by openclaw doctor)
  systemd.services.openclaw-gateway.environment = {
    NODE_COMPILE_CACHE = "/var/tmp/openclaw-compile-cache";
    OPENCLAW_NO_RESPAWN = "1";
  };

  # Xvfb virtual framebuffer — Chromium needs a DISPLAY even in headless mode
  systemd.services.xvfb = {
    description = "Xvfb virtual framebuffer on :99";
    wantedBy = [ "multi-user.target" ];
    before = [ "chromium-cdp.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  # Persistent headless Chromium with CDP on port 18800
  systemd.services.chromium-cdp = {
    description = "Headless Chromium with Chrome DevTools Protocol";
    after = [ "xvfb.service" ];
    requires = [ "xvfb.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "openclaw-gateway.service" ];
    environment = {
      DISPLAY = ":99";
      DBUS_SESSION_BUS_ADDRESS = "/dev/null";
    };
    serviceConfig = {
      User = "openclaw";
      Group = "openclaw";
      ExecStart = "${pkgs.chromium}/bin/chromium --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --remote-debugging-port=18800 --remote-debugging-address=127.0.0.1 --user-data-dir=/var/lib/openclaw/.chromium-data";
      Restart = "always";
      RestartSec = "3s";
    };
  };

  systemd.services.openclaw-gateway.after = [ "chromium-cdp.service" ];
  systemd.services.openclaw-gateway.requires = [ "chromium-cdp.service" ];

  systemd.tmpfiles.rules = [
    "d /var/tmp/openclaw-compile-cache 0755 openclaw openclaw -"
    "d /var/lib/openclaw/.chromium-data 0750 openclaw openclaw -"
    "L+ /usr/bin/google-chrome - - - - /run/current-system/sw/bin/chromium"
  ];

  environment.systemPackages = with pkgs; [ socat gh chromium xorg.xorgserver ];


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
