{ modulesPath, pkgs, name, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking = {
    hostName   = "silas";
    enableIPv6 = false;
    dhcpcd.enable = false;
    useDHCP       = false;
    useHostResolvConf = false;
  };

  systemd.network = {
    enable = true;
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP         = "ipv4";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # OpenClaw service
  services.openclaw = {
    enable = true;
    openFirewall = true;
    deployPersonalityFiles = true;
  };

  # Secrets (uncomment when sops-nix keys are generated)
  # sops.secrets."anthropic-api-key" = {};
  # services.openclaw.secretsFile = config.sops.secrets."anthropic-api-key".path;

  system.stateVersion = "25.11";
}
