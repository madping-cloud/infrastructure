{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "cso"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
  systemd.network = { enable = true; networks."50-eth0" = { matchConfig.Name = "eth0"; networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = false; }; linkConfig.RequiredForOnline = "routable"; }; };
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.validateSopsFiles = false;
  # Shared secrets (all 6 shared keys)
  sops.secrets.shared_anthropic_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "anthropic_api_key"; };
  sops.secrets.shared_openai_api_key     = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openai_api_key"; };
  sops.secrets.shared_google_ai_api_key  = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "google_ai_api_key"; };
  sops.secrets.shared_groq_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "groq_api_key"; };
  sops.secrets.shared_openrouter_api_key = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "openrouter_api_key"; };
  sops.secrets.shared_vast_api_key       = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "vast_api_key"; };
  sops.secrets.shared_peer_gateway_token = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "peer_gateway_token"; };
  # Container-specific secrets
  sops.secrets.gateway_token  = { sopsFile = "/etc/nixos/secrets/${host}/cso.yaml"; key = "gateway_token"; };
  sops.secrets.tavily_api_key = { sopsFile = "/etc/nixos/secrets/${host}/cso.yaml"; key = "tavily_api_key"; };
  sops.secrets.discord_token  = { sopsFile = "/etc/nixos/secrets/${host}/cso.yaml"; key = "discord_token"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18008" "https://10.100.0.1" "https://10.100.0.1:18008" ];
    gateway.httpToolsAllow = [ "sessions_send" ];
    userName = "Marc";
    primaryModel = "anthropic/claude-sonnet-4-6";
    fallbackModels = [
      "anthropic/claude-opus-4-6"
      "google/gemini-2.5-pro"
      "openrouter/meta-llama/llama-4-maverick"
    ];
    availableModels = [
      # Anthropic (direct — primary, on subscription)
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      "anthropic/claude-haiku-4-5"
      # Google (direct)
      "google/gemini-2.5-pro"
      "google/gemini-2.5-flash"
      # OpenAI (direct)
      "openai/gpt-4o"
      # OpenRouter — cheap capable workers
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/meta-llama/llama-4-scout"
    ];
    modelAliases = {
      "anthropic/claude-sonnet-4-6"            = "sonnet";          # Default — strategy, planning
      "anthropic/claude-opus-4-6"              = "opus";            # Deep reasoning, hard pivots
      "anthropic/claude-haiku-4-5"             = "haiku";           # Fast mechanical tasks
      "google/gemini-2.5-pro"                  = "gemini-pro";      # Google's best
      "google/gemini-2.5-flash"                = "gemini-flash";    # Fast multimodal
      "openai/gpt-4o"                          = "gpt-4o";          # OpenAI flagship
      "openrouter/meta-llama/llama-4-maverick" = "llama-maverick";  # $0.15/1M — large context tasks
      "openrouter/meta-llama/llama-4-scout"    = "llama-scout";     # $0.08/1M — cheapest worker
    };
    webSearch.provider = "tavily";
    webSearch.tavily.enable = true;
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
