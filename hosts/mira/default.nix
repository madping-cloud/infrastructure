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
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "openrouter_api_key"; };
  sops.secrets.xai_api_key         = { sopsFile = "/etc/nixos/secrets/${host}/mira.yaml"; key = "xai_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18004" "https://10.100.0.1" "https://10.100.0.1:18004" ];
    userName = "Marc";
    primaryModel = "anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "anthropic/claude-opus-4-6"
      "google/gemini-2.5-pro"
      "openrouter/mistralai/mistral-large"
    ];
    availableModels = [
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      "google/gemini-2.5-pro"
      "google/gemini-2.5-flash"
      "openrouter/mistralai/mistral-large"
      "openrouter/meta-llama/llama-4-maverick"
    ];
    modelAliases = {
      "anthropic/claude-sonnet-4-6"            = "sonnet";
      "anthropic/claude-opus-4-6"              = "opus";
      "anthropic/claude-haiku-4-5"             = "haiku";
      "google/gemini-2.5-pro"                  = "gemini-pro";
      "google/gemini-2.5-flash"                = "gemini-flash";
      "openrouter/mistralai/mistral-large"     = "mistral-large";
      "openrouter/meta-llama/llama-4-maverick" = "llama-maverick";
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
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
