{ config, pkgs, lib, inputs, ... }:

# _template — New Host Template
#
# Copy this directory to hosts/<hostname>/ when adding a new host.
# Fill in the TODO sections below.

{
  imports = [
    ../../modules/common/default.nix
    # Add service modules here:
    # ../../modules/services/openclaw.nix
  ];

  # TODO: Set the hostname
  networking.hostName = "CHANGEME";

  # TODO: Configure networking
  # networking.useDHCP = true;
  # -- OR --
  # networking.useDHCP = false;
  # networking.interfaces.eth0.ipv4.addresses = [
  #   { address = "10.100.0.X"; prefixLength = 24; }
  # ];

  # TODO: Add host-specific packages
  environment.systemPackages = with pkgs; [
    # ...
  ];

  # TODO: Enable services
  # services.openclaw.enable = true;
}
