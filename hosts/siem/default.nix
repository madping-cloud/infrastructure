{ config, modulesPath, pkgs, name, host, ... }:
{
  imports = [ "${modulesPath}/virtualisation/lxc-container.nix" ];
  networking = { hostName = "siem"; enableIPv6 = false; dhcpcd.enable = false; useDHCP = false; useHostResolvConf = false; };
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
  sops.secrets.shared_cluster_gateway_token = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "cluster_gateway_token"; };
  # Container-specific secrets
  sops.secrets.gateway_token  = { sopsFile = "/etc/nixos/secrets/${host}/siem.yaml"; key = "gateway_token"; };
  sops.secrets.discord_token  = { sopsFile = "/etc/nixos/secrets/${host}/siem.yaml"; key = "discord_token"; };
  services.openclaw = {
    enable = true; openFirewall = true; secretsFile = "/run/openclaw-env";
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18010" "https://10.100.0.1" "https://10.100.0.1:18010" ];
    gateway.bind = "lan";
    gateway.chatCompletions.enable = true;
    userName = "Marc";
    primaryModel = "anthropic/claude-haiku-4-5";
    fallbackModels = [
      "anthropic/claude-sonnet-4-6"
      "openrouter/meta-llama/llama-4-maverick"
    ];
    availableModels = [
      # Anthropic (direct — primary, on subscription)
      "anthropic/claude-haiku-4-5"
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-opus-4-6"
      # OpenRouter — cheap capable workers
      "openrouter/meta-llama/llama-4-maverick"
      "openrouter/meta-llama/llama-4-scout"
      "openrouter/google/gemini-2.5-flash-lite"
    ];
    modelAliases = {
      "anthropic/claude-haiku-4-5"               = "haiku";            # Default — fast triage, alerts
      "anthropic/claude-sonnet-4-6"              = "sonnet";           # Incident investigation
      "anthropic/claude-opus-4-6"                = "opus";             # Deep threat analysis
      "openrouter/meta-llama/llama-4-maverick"   = "llama-maverick";   # $0.15/1M — large log analysis
      "openrouter/meta-llama/llama-4-scout"      = "llama-scout";      # $0.08/1M — cheapest worker
      "openrouter/google/gemini-2.5-flash-lite"  = "gemini-flash-lite"; # Large context analysis
    };
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    # No telegram, no webSearch
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
      ExecStart = pkgs.writeShellScript "openclaw-bridge-start" ''
        IP=$(${pkgs.iproute2}/bin/ip -4 addr show eth0 | ${pkgs.gawk}/bin/awk '/inet / {print $2}' | ${pkgs.coreutils}/bin/cut -d/ -f1)
        exec ${pkgs.socat}/bin/socat TCP-LISTEN:18790,fork,reuseaddr,bind=0.0.0.0 "TCP:$IP:18789"
      '';
      Restart = "always";
      RestartSec = "3s";
    };
  };

  networking.firewall.allowedTCPPorts = [ 18790 ];
  system.stateVersion = "25.11";
}
