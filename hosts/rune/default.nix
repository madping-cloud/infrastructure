{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "rune"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false;
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "discord_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "gateway_token"; };
  sops.secrets.anthropic_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "anthropic_api_key"; };
  sops.secrets.openai_api_key      = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "openai_api_key"; };
  sops.secrets.google_ai_api_key   = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "google_ai_api_key"; };
  sops.secrets.groq_api_key        = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "groq_api_key"; };
  sops.secrets.openrouter_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/rune.yaml"; key = "openrouter_api_key"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    userName = "Marc";
    # Personality work is creative-editorial, not deep-reasoning.
    # Sonnet handles it well and is on the Claude Code subscription.
    primaryModel = "anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      "openrouter/meta-llama/llama-4-scout"
    ];
    availableModels = [
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/google/gemini-2.5-flash-lite"
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/mistralai/mistral-small-2603"
    ];
    modelAliases = {
      "anthropic/claude-sonnet-4-6"             = "sonnet";
      "anthropic/claude-opus-4-6"               = "opus";
      "anthropic/claude-haiku-4-5"              = "haiku";
      "openrouter/meta-llama/llama-4-scout"     = "llama-scout";
      "openrouter/google/gemini-2.5-flash-lite" = "gemini-flash-lite";
      "openrouter/meta-llama/llama-4-maverick"  = "llama-maverick";
      "openrouter/mistralai/mistral-small-2603" = "mistral-small";
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
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
