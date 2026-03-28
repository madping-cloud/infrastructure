{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/openclaw.nix
    ../../modules/hardening.nix
  ];

  # Host identity
  networking.hostName = "workbench";

  # Container networking (Incus manages DHCP/DNS)
  networking.useDHCP = true;

  # OpenClaw service (disabled until fully configured)
  services.openclaw = {
    enable = false;  # Enable after secrets are wired up
  };

  # Container-specific: no bootloader needed
  boot.loader.grub.enable = false;
  boot.isContainer = true;

  # Additional host-specific packages
  environment.systemPackages = with pkgs; [
    tree
    ripgrep
    ncdu
  ];
}
