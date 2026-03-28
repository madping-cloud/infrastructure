{
  description = "madping-cloud infrastructure — NixOS + Incus GitOps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... } @ inputs:
  let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
    lib    = nixpkgs.lib;

    # Helper: build a NixOS container config
    mkAgent = { name, hostModule }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs name; };
      modules = [
        sops-nix.nixosModules.sops
        ./modules/common/default.nix
        ./modules/services/openclaw.nix
        hostModule
      ];
    };

  in {

    # ── Agent Containers ──────────────────────────────────────────────────────
    # Each agent is a NixOS Incus container with OpenClaw installed.
    # Add a new agent: copy hosts/_template/, set name, add entry here.

    nixosConfigurations = {

      # Silas — executor/craftsman agent (Marc's second brain)
      silas = mkAgent {
        name       = "silas";
        hostModule = ./hosts/silas/default.nix;
      };

      # Aurora — Connie's companion agent
      aurora = mkAgent {
        name       = "aurora";
        hostModule = ./hosts/aurora/default.nix;
      };

      # Atlas — Marc's primary assistant (currently bare Thor, future: container)
      atlas = mkAgent {
        name       = "atlas";
        hostModule = ./hosts/atlas/default.nix;
      };

    };

    # ── Dev Shell ─────────────────────────────────────────────────────────────
    devShells.${system}.default = pkgs.mkShell {
      name = "infra-dev";
      packages = with pkgs; [ git sops age jq nixos-rebuild ];
      shellHook = ''
        echo "🔧 madping-cloud infrastructure"
        echo "   nixos-rebuild switch --flake .#silas   — rebuild silas"
        echo "   nixos-rebuild switch --flake .#aurora  — rebuild aurora"
        echo "   nixos-rebuild switch --flake .#atlas   — rebuild atlas"
      '';
    };

  };
}
