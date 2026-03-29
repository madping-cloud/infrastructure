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
  sops.secrets.discord_token       = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "discord_token"; };
  sops.secrets.telegram_token      = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "telegram_token"; };
  sops.secrets.gateway_token       = { sopsFile = "/etc/nixos/secrets/${host}/cole.yaml"; key = "gateway_token"; };
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
      "google/imagen-4"
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
      # OpenRouter — cheap/free background models
      "openrouter/nvidia/nemotron-3-super-120b-a12b:free"  = "nemotron-free";  # $0 — mechanical background work
      "openrouter/inception/mercury-2"                     = "mercury";        # 1000+ tok/s — fast one-shots
      "openrouter/mistralai/mistral-small-2603"            = "mistral-small";  # EU, multimodal — creative tasks
      "openrouter/google/gemini-3.1-flash-lite-preview"    = "gemini-flash-lite"; # 1M ctx — long-context/multimodal
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
  };
  system.stateVersion = "25.11";
}
