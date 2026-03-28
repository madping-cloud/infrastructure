{ modulesPath, pkgs, name, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking = {
    hostName   = "atlas";
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

  system.stateVersion = "25.11";
}
