{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "cole"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
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
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "gateway_token"; };
  sops.secrets.tavily_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "tavily_api_key"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "openrouter_api_key"; };
  sops.secrets.xai_api_key         = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "xai_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    primaryModel = "anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      "google/gemini-2.5-flash"
    ];
    availableModels = [
      # Anthropic (Claude Code sub — use freely)
      "anthropic/claude-haiku-4-5"
      # Google
      "google/gemini-2.5-flash"
      "google/imagen-4"
      # xAI
      "x-ai/grok-4.20-0309-reasoning"
      "x-ai/grok-4.20-0309-non-reasoning"
      "x-ai/grok-4.20-multi-agent-0309"
      "x-ai/grok-4-1-fast-reasoning"
      "x-ai/grok-4-1-fast-non-reasoning"
    ];
    # Models with aliases (used for /model switching and subagent routing)
    modelAliases = {
      "anthropic/claude-sonnet-4-6"                        = "sonnet";
      "anthropic/claude-opus-4-6"                          = "opus";
      "anthropic/claude-haiku-4-5"                         = "haiku";
      # Google
      "google/gemini-2.5-flash"                            = "gemini-flash";
      # xAI
      "x-ai/grok-4.20-0309-non-reasoning"                  = "grok";
      "x-ai/grok-4.20-0309-reasoning"                      = "grok-think";
      "x-ai/grok-4.20-multi-agent-0309"                    = "grok-multi";
      "x-ai/grok-4-1-fast-non-reasoning"                   = "grok-fast";
      "x-ai/grok-4-1-fast-reasoning"                       = "grok-fast-think";
      # OpenRouter — cost-optimized background/subagent models (no China)
      "openrouter/meta-llama/llama-4-scout"                = "llama-scout";       # $0.08/1M — Llama 4, 327k ctx, multimodal, cheapest capable worker (Meta/US)
      "openrouter/google/gemini-2.5-flash-lite"            = "gemini-flash-lite"; # $0.10/1M — 1M ctx, full multimodal (audio/video/image), tools (Google/US)
      "openrouter/meta-llama/llama-4-maverick"             = "llama-maverick";    # $0.15/1M — Llama 4 flagship, 1M ctx, multimodal, capable agent (Meta/US)
      "openrouter/mistralai/mistral-small-2603"            = "mistral-small";     # $0.15/1M — 262k ctx, multimodal, reasoning, creative tasks (Mistral/France)
      "openrouter/inception/mercury-2"                     = "mercury";           # $0.25/1M — 1000+ tok/s diffusion LLM, speed-critical tasks (Inception/US)
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    telegram.enable = true;
    telegram.dmPolicy = "allowlist";
    telegram.allowFrom = [ "5201076941" ];
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18001" "https://10.100.0.1" "https://10.100.0.1:18001" ];
    gateway.httpToolsAllow = [ "sessions_send" ];
    webSearch.provider = "tavily";
    webSearch.tavily.enable = true;
  };
  # Startup performance optimizations (recommended by openclaw doctor)
  systemd.services.openclaw-gateway.environment = {
    NODE_COMPILE_CACHE = "/var/tmp/openclaw-compile-cache";
    OPENCLAW_NO_RESPAWN = "1";
  };
  systemd.tmpfiles.rules = [
    "d /var/tmp/openclaw-compile-cache 0755 openclaw openclaw -"
  ];

  environment.systemPackages = with pkgs; [ socat ];


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
