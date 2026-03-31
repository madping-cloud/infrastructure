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
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/atlas.yaml"; key = "openrouter_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "http://192.168.4.6" "http://10.100.0.1" ];
    userName = "Marc";
    primaryModel = "google/gemini-2.5-flash";
    fallbackModels = [
      "anthropic/claude-sonnet-4-6"
      "openrouter/meta-llama/llama-4-maverick"
    ];
    availableModels = [
      # Google (direct — default, strong multimodal)
      "google/gemini-2.5-flash"
      "google/gemini-2.5-flash-lite"
      "google/imagen-4"
      # Anthropic (direct — high quality, reliable)
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-haiku-4-5"
      # OpenRouter — cheap capable workers
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/mistralai/mistral-small-2603"
      "openrouter/inception/mercury-2"
      "openrouter/google/gemini-2.5-flash-lite"
    ];
    modelAliases = {
      "google/gemini-2.5-flash"                = "gemini-flash";       # Default — fast, multimodal, conversational
      "google/gemini-2.5-flash-lite"           = "gemini-flash-lite";  # Lighter/cheaper Google
      "anthropic/claude-sonnet-4-6"            = "sonnet";             # Best reasoning, reliable, on subscription
      "anthropic/claude-haiku-4-5"             = "haiku";              # Fastest Claude, mechanical tasks
      "openrouter/meta-llama/llama-4-scout"    = "llama-scout";        # $0.08/1M — cheapest capable worker
      "openrouter/meta-llama/llama-4-maverick" = "llama-maverick";     # $0.15/1M — 1M ctx, multi-step tasks
      "openrouter/mistralai/mistral-small-2603" = "mistral-small";     # $0.15/1M — creative/narrative
      "openrouter/inception/mercury-2"          = "mercury";           # $0.25/1M — 1000+ tok/s, text-only
      "openrouter/google/gemini-2.5-flash-lite" = "or-gemini-lite";    # OpenRouter path for Gemini lite
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    discord.threadBindings.enable = true;
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
  system.stateVersion = "25.11";
}
