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
    userName = "Marc";
    primaryModel = "xai/grok-4.20-0309-reasoning";
    fallbackModels = [ "google/gemini-2.5-flash" ];
    availableModels = [
      "google/gemini-2.5-flash"
      "google/imagen-4"
      "xai/grok-4.20-0309-reasoning"
      "xai/grok-4.20-0309-non-reasoning"
      "xai/grok-4-1-fast-reasoning"
      "xai/grok-4-1-fast-non-reasoning"
    ];
    customModelProviders.xai = {
      baseUrl = "https://api.x.ai/v1";
      api = "openai-responses";
      models = [
        { id = "grok-4.20-0309-reasoning"; name = "Grok 4.20 (Reasoning)"; reasoning = true; input = [ "text" "image" ]; cost = { input = 2; output = 6; cacheRead = 0.2; cacheWrite = 0; }; contextWindow = 2000000; maxTokens = 30000; }
        { id = "grok-4.20-0309-non-reasoning"; name = "Grok 4.20 (Non-Reasoning)"; reasoning = false; input = [ "text" "image" ]; cost = { input = 2; output = 6; cacheRead = 0.2; cacheWrite = 0; }; contextWindow = 2000000; maxTokens = 30000; }
        { id = "grok-4-1-fast-reasoning"; name = "Grok 4.1 Fast (Reasoning)"; reasoning = true; input = [ "text" "image" ]; cost = { input = 0.2; output = 0.5; cacheRead = 0.05; cacheWrite = 0; }; contextWindow = 2000000; maxTokens = 30000; }
        { id = "grok-4-1-fast-non-reasoning"; name = "Grok 4.1 Fast (Non-Reasoning)"; reasoning = false; input = [ "text" "image" ]; cost = { input = 0.2; output = 0.5; cacheRead = 0.05; cacheWrite = 0; }; contextWindow = 2000000; maxTokens = 30000; }
      ];
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
  };
  system.stateVersion = "25.11";
}
