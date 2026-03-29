{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "aurora"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false; # secrets live at runtime paths not available during nix eval
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.shared_vast_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "vast_api_key"; };
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/aurora.yaml"; key = "openrouter_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    userName = "Connie";
    primaryModel = "google/gemini-2.5-flash";
    fallbackModels = [ "google/gemini-2.5-flash-lite" "google/imagen-4" ];
    availableModels = [
      # Google (direct — default voice, warm and conversational)
      "google/gemini-2.5-flash"
      "google/gemini-2.5-flash-lite"
      "google/imagen-4"
    ];
    # Models with aliases — cheap options via OpenRouter (China allowed for Aurora)
    modelAliases = {
      "google/gemini-2.5-flash"                          = "gemini-flash";      # Default — warm, multimodal, conversational
      "google/gemini-2.5-flash-lite"                     = "gemini-flash-lite"; # $0.10/1M — 1M ctx, lighter/cheaper Google
      "openrouter/qwen/qwen3.5-flash-02-23"              = "qwen-flash";        # $0.065/1M — 1M ctx, multimodal, tools, reasoning. Cheapest capable worker.
      "openrouter/deepseek/deepseek-v3.2"                = "deepseek-v3";       # $0.26/1M — 163k ctx, tools + reasoning. Best quality/value for complex questions.
      "openrouter/qwen/qwen3-235b-a22b-thinking-2507"    = "qwen-think";        # $0.15/$1.50 — Deep reasoning. Use sparingly (output is pricey).
      "openrouter/mistralai/mistral-small-2603"          = "mistral-small";     # $0.15/1M — creative writing, narrative, storytelling (French sensibility)
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    telegram.enable = true;
    telegram.allowFrom = [ "8580758213" "5201076941" ];
  };
  system.stateVersion = "25.11";
}
