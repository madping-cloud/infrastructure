{ lib, ... }:

# lib/default.nix — Shared helpers for this flake.
#
# Import in flake.nix as:
#   localLib = import ./lib { inherit lib; };

rec {
  # Build a NixOS system with common defaults applied.
  # Usage:
  #   nixosConfigurations.workbench = localLib.mkContainer {
  #     inherit nixpkgs system;
  #     hostModule = ./hosts/thor/containers/openclaw.nix;
  #   };
  mkSystem = { nixpkgs, system, hostModule, extraModules ? [], specialArgs ? {} }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = specialArgs;
      modules = [ hostModule ] ++ extraModules;
    };

  # Convenience: build a container NixOS config (sets boot.isContainer defaults)
  mkContainer = { nixpkgs, system, hostModule, extraModules ? [], specialArgs ? {} }:
    mkSystem {
      inherit nixpkgs system specialArgs;
      hostModule = hostModule;
      extraModules = extraModules ++ [
        { boot.isContainer = lib.mkDefault true; }
      ];
    };
}
