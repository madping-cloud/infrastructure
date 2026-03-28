{ config, pkgs, lib, ... }:

# OpenClaw service module
# Installs Node.js and sets up OpenClaw as a systemd service.
# Secrets (API keys, tokens) are managed via sops-nix (see secrets/).

{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant daemon";

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/root/.openclaw/workspace";
      description = "OpenClaw workspace directory";
    };

    nodeVersion = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs_22;
      description = "Node.js package to use";
    };
  };

  config = lib.mkIf config.services.openclaw.enable {
    environment.systemPackages = [
      config.services.openclaw.nodeVersion
      pkgs.git
    ];

    # Ensure workspace directory exists
    systemd.tmpfiles.rules = [
      "d ${config.services.openclaw.workDir} 0700 root root -"
    ];

    # OpenClaw gateway service
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = "/root";
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${config.services.openclaw.nodeVersion}/bin/node /root/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/bin/openclaw.js gateway start --foreground";
        Restart = "on-failure";
        RestartSec = "10s";
        # EnvironmentFile = "/run/secrets/openclaw-env";  # Uncomment when sops-nix is configured
      };
    };
  };
}
