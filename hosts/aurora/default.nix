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
  sops.secrets.shared_peer_gateway_token = { sopsFile = "/etc/nixos/secrets/${host}/shared.yaml"; key = "peer_gateway_token"; };
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
    gateway.allowedOrigins = [ "https://192.168.4.6" "https://192.168.4.6:18003" "https://10.100.0.1" "https://10.100.0.1:18003" ];
    gateway.bind = "lan";
    tools.sessionsVisibility = "all";
    tools.agentToAgent = true;
    gateway.httpToolsAllow = [ "sessions_send" ];
    userName = "Connie";
    primaryModel = "google/gemini-2.5-flash";
    fallbackModels = [ "openrouter/deepseek/deepseek-v3.2" "google/gemini-2.5-flash-lite" ];
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
    toolsAllow = [ "cron" ];  # Allow Aurora to manage her own cron jobs
    discord.enable = true;
    discord.allowFrom = [ "166609345080066048" ];
    telegram.enable = true;
    telegram.allowFrom = [ "8580758213" "5201076941" ];
  };
  # Connie scheduled messages — systemd timers (bypasses agent runtime for reliability)
  environment.systemPackages = [ pkgs.jq  pkgs.socat ];

  systemd.services.connie-send-wakeup = {
    description = "Send Connie wakeup message";
    serviceConfig = {
      Type = "oneshot";
      User = "openclaw";
      ExecStart = "/usr/local/bin/connie-send.sh wakeup";
    };
  };
  systemd.services.connie-send-daytime = {
    description = "Send Connie daytime message";
    serviceConfig = {
      Type = "oneshot";
      User = "openclaw";
      ExecStart = "/usr/local/bin/connie-send.sh daytime";
    };
  };
  systemd.services.connie-send-goodnight = {
    description = "Send Connie goodnight message";
    serviceConfig = {
      Type = "oneshot";
      User = "openclaw";
      ExecStart = "/usr/local/bin/connie-send.sh goodnight";
    };
  };

  systemd.timers.connie-send-wakeup = {
    description = "Connie wakeup message timer (12:00 PM)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 12:00:00";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
  systemd.timers.connie-send-daytime = {
    description = "Connie daytime message timer (4:30 PM)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 16:30:00";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };
  systemd.timers.connie-send-goodnight = {
    description = "Connie goodnight message timer (2:00 AM)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };

  # Deploy connie-send.sh script
  system.activationScripts.connieSendScript = {
    text = ''
      install -m 755 -o root -g root /dev/stdin /usr/local/bin/connie-send.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
CATEGORY="''${1:-daytime}"
MESSAGES_FILE="/var/lib/openclaw/workspace/connie_messages.json"
OPENCLAW="/var/lib/openclaw/.npm-global/bin/openclaw"
CONNIE_ID="8580758213"
if [ ! -f "$MESSAGES_FILE" ]; then echo "ERROR: $MESSAGES_FILE not found" >&2; exit 1; fi
MESSAGE=$(${pkgs.jq}/bin/jq -r --arg cat "$CATEGORY" '.[$cat][]' "$MESSAGES_FILE" | ${pkgs.coreutils}/bin/shuf -n 1)
if [ -z "$MESSAGE" ]; then echo "ERROR: No messages for category: $CATEGORY" >&2; exit 1; fi
echo "[$(date -Iseconds)] Sending $CATEGORY to Connie: $MESSAGE"
"$OPENCLAW" message send --channel telegram -t "$CONNIE_ID" -m "$MESSAGE"
SCRIPT
    '';
    deps = [];
  };

  # Startup performance optimizations (recommended by openclaw doctor)
  systemd.services.openclaw-gateway.environment = {
    NODE_COMPILE_CACHE = "/var/tmp/openclaw-compile-cache";
    OPENCLAW_NO_RESPAWN = "1";
  };
  systemd.tmpfiles.rules = [
    "d /var/tmp/openclaw-compile-cache 0755 openclaw openclaw -"
  ];

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
