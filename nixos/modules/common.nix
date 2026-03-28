{ config, pkgs, lib, ... }:

{
  # Locale & timezone
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Basic packages available everywhere
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    jq
  ];

  # SSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      X11Forwarding = false;
    };
  };

  # Root user with authorized keys placeholder
  users.users.root = {
    openssh.authorizedKeys.keys = [
      # Add SSH public keys here
    ];
  };

  # Nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # System state version — do not change after initial deploy
  system.stateVersion = "25.11";
}
