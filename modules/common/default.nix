{ config, pkgs, lib, ... }:

# Common base configuration applied to all hosts.
# Includes: locale, timezone, SSH, base packages, nix settings, firewall.

{
  # ── Locale & Timezone ───────────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Base Packages ───────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    jq
    tree
    ripgrep
    ncdu
    age
    sops
  ];

  # ── SSH ─────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      X11Forwarding = false;
    };
  };

  # Root authorized keys — add SSH public keys here
  users.users.root = {
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... user@host"
    ];
  };

  # ── Firewall ─────────────────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
    ];
    allowPing = true;
  };

  # ── Kernel Hardening ─────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter"          = 1;
    "net.ipv4.conf.default.rp_filter"      = 1;
    "net.ipv4.conf.all.accept_redirects"   = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects"     = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects"   = 0;
    "kernel.randomize_va_space"            = 2;
    "kernel.dmesg_restrict"                = 1;
    "kernel.kptr_restrict"                 = 2;
  };

  # ── Audit ─────────────────────────────────────────────────────────────────────
  security.auditd.enable = lib.mkDefault true;
  security.audit.enable = lib.mkDefault true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];

  # ── Disable Unnecessary Services ─────────────────────────────────────────────
  services.avahi.enable = lib.mkDefault false;

  # ── Nix Settings ─────────────────────────────────────────────────────────────
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
