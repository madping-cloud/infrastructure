{ nixpkgs, sops-nix, system, ... }:

# lib/default.nix — Shared helpers for this flake.
#
# Import in flake.nix as:
#   localLib = import ./lib { inherit nixpkgs sops-nix system; };
#
# Then use:
#   nixosConfigurations.cole = localLib.mkAgent { name = "cole"; hostModule = ./hosts/cole/default.nix; };

{
  # Build a NixOS agent container config with common modules applied.
  # Each agent gets: sops-nix, common module, openclaw service module, and its host module.
  #
  # Usage:
  #   nixosConfigurations.cole = localLib.mkAgent {
  #     name       = "cole";
  #     host       = "thor";   # host machine name (used for secret paths)
  #     hostModule = ./hosts/cole/default.nix;
  #   };
  mkAgent = { name, host ? "thor", hostModule }: nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit name host; inputs = { inherit nixpkgs sops-nix; }; };
    modules = [
      sops-nix.nixosModules.sops
      ../modules/common/default.nix
      ../modules/services/openclaw.nix
      hostModule
    ];
  };
}
