{ config, modulesPath, pkgs, name, ... }:

# Template for a new agent container.
# 1. Copy this directory: cp -r hosts/_template hosts/<agentname>
# 2. Set hostName to your agent name (replace "CHANGE_ME" below)
# 3. Add nixosConfigurations entry in flake.nix
# 4. Run: nixos-rebuild switch --flake .#<agentname>

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  # Safety net: fail loudly if the template hostname was never changed.
  assertions = [
    {
      assertion = config.networking.hostName != "CHANGE_ME";
      message   = "You forgot to set the hostname! Edit hosts/<name>/default.nix and replace CHANGE_ME.";
    }
  ];

  networking = {
    hostName   = "CHANGE_ME";  # ← CHANGE THIS
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

  services.openclaw = {
    enable = true;
    openFirewall = true;
    deployPersonalityFiles = true;
  };

  system.stateVersion = "25.11";
}
