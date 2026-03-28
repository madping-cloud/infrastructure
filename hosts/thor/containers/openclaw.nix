{ config, pkgs, lib, ... }:

# Thor › workbench container
#
# Incus container running the OpenClaw AI assistant.
# Static IP: 10.100.0.21 (assigned via Incus device profile or /etc/network/interfaces)
# Hostname: workbench
#
# This file is the NixOS configuration *inside* the container.
# The Incus container itself is provisioned by Thor's host config.

{
  imports = [
    ../../../modules/common/default.nix
    ../../../modules/services/openclaw.nix
  ];

  # ── Host Identity ─────────────────────────────────────────────────────────
  networking.hostName = "workbench";

  # ── Container Boot ────────────────────────────────────────────────────────
  # Incus containers don't use a bootloader.
  boot.loader.grub.enable = false;
  boot.isContainer = true;

  # ── Networking ────────────────────────────────────────────────────────────
  # Static IP within the Incus bridge network.
  # The Incus host (Thor) routes 10.100.0.0/24 to its containers.
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address      = "10.100.0.21";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.100.0.1";
  networking.nameservers = [ "10.100.0.1" "1.1.1.1" ];

  # ── OpenClaw Service ──────────────────────────────────────────────────────
  services.openclaw = {
    enable = true;

    # Secrets file — wire to sops-nix output once keys are configured:
    # secretsFile = config.sops.secrets."openclaw-env".path;
    secretsFile = null;

    # Open gateway port within the container (still behind Incus NAT)
    openFirewall = true;

    # Deploy personality skeleton files on activation
    deployPersonalityFiles = true;
  };

  # ── Container-Specific Packages ───────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Already in common: vim git curl wget htop jq tree ripgrep ncdu age sops
    tmux
    nix-tree   # visualize closure sizes
  ];

  # ── Container-Specific Firewall ───────────────────────────────────────────
  # SSH is already opened by common. Openclaw opens 8080 via openFirewall above.
  # Add any container-specific ports here.
}
