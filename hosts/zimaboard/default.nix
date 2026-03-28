{ config, pkgs, lib, inputs, ... }:

# ZimaBoard — Future Host (template)
#
# ZimaBoard is a low-power x86 SBC planned for future use.
# This is a template placeholder — flesh out when the board is provisioned.

{
  imports = [
    ../../modules/common/default.nix
  ];

  networking.hostName = "zimaboard";

  # ZimaBoard uses systemd-boot on x86
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  # TODO: Add ZimaBoard-specific hardware config
  # TODO: Add services this board will run
}
