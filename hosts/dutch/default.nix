{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "dutch"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false;
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.shared_vast_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "vast_api_key"; };
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/dutch.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/dutch.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/dutch.yaml"; key = "gateway_token"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    userName = "Marc";
    primaryModel = "openrouter/deepseek/deepseek-v3.2";
    fallbackModels = [
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/google/gemini-2.5-flash-lite"
    ];
    availableModels = [
      "openrouter/deepseek/deepseek-v3.2"
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/google/gemini-2.5-flash-lite"
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/mistralai/mistral-small-2603"
      "openrouter/inception/mercury-2"
      "openrouter/google/gemini-2.5-flash"
    ];
    modelAliases = {
      "openrouter/deepseek/deepseek-v3.2"               = "deepseek-v3";
      "openrouter/meta-llama/llama-4-scout"             = "llama-scout";
      "openrouter/google/gemini-2.5-flash-lite"         = "gemini-flash-lite";
      "openrouter/meta-llama/llama-4-maverick"          = "llama-maverick";
      "openrouter/mistralai/mistral-small-2603"         = "mistral-small";
      "openrouter/inception/mercury-2"                  = "mercury";
      "openrouter/google/gemini-2.5-flash"              = "gemini-flash";
    };
    webSearch.provider = "tavily";
    webSearch.tavily.enable = true;
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    telegram.enable = true;
    telegram.dmPolicy = "allowlist";
    telegram.allowFrom = [ "5201076941" ];
  };
  # Startup performance optimizations
  systemd.services.openclaw-gateway.environment = {
    NODE_COMPILE_CACHE = "/var/tmp/openclaw-compile-cache";
    OPENCLAW_NO_RESPAWN = "1";
  };
  systemd.tmpfiles.rules = [
    "d /var/tmp/openclaw-compile-cache 0755 openclaw openclaw -"
  ];
  system.stateVersion = "25.11";
}
