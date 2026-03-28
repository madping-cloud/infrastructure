{ config, pkgs, lib, inputs, ... }:

# Thor — Incus Host (bare metal)
#
# Thor is the physical host running Incus to manage containers.
# This configuration is for Thor itself, not its containers.
# Container configs live in hosts/thor/containers/.

{
  imports = [
    ../../modules/common/default.nix
  ];

  networking.hostName = "thor";

  # Thor runs Incus to manage containers
  virtualisation.incus = {
    enable = true;
  };

  # Thor is a bare-metal host — it has a bootloader
  # (Hardware-specific: override in hardware-configuration.nix if using NixOS)
  # boot.loader.systemd-boot.enable = true;

  # Additional packages for the Incus host
  environment.systemPackages = with pkgs; [
    incus
    colmena   # deployment tool
  ];

  # Open Incus bridge network
  networking.bridges.incusbr0 = {
    interfaces = [];
  };

  networking.interfaces.incusbr0 = {
    ipv4.addresses = [
      { address = "10.100.0.1"; prefixLength = 24; }
    ];
  };

  # NAT for containers
  networking.nat = {
    enable = true;
    internalInterfaces = [ "incusbr0" ];
    externalInterface = "eth0";  # Adjust to actual WAN interface
  };
}
