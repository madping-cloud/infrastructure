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

    # Load shared helpers from lib/
    localLib = import ./lib { inherit nixpkgs sops-nix system; };

    # Helper alias for readability
    mkAgent = localLib.mkAgent;

  in {

    # ── Agent Containers ──────────────────────────────────────────────────────
    # Each agent is a NixOS Incus container with OpenClaw installed.
    # Add a new agent: copy hosts/_template/, set hostname, add entry here.

    nixosConfigurations = {

      # Cole — infrastructure agent (Marc's second brain)
      cole = mkAgent {
        name       = "cole";
        hostModule = ./hosts/cole/default.nix;
      };

      # Aurora — Connie's companion agent
      aurora = mkAgent {
        name       = "aurora";
        hostModule = ./hosts/aurora/default.nix;
      };


      # Atlas — primary assistant agent
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
        echo "madping-cloud infrastructure"
        echo "   nixos-rebuild switch --flake .#cole    — rebuild cole"
        echo "   nixos-rebuild switch --flake .#aurora  — rebuild aurora"
        if [ -d .git ] && [ ! -L .git/hooks/pre-commit ]; then
          ln -sf ../../scripts/pre-commit-check.sh .git/hooks/pre-commit
          echo "   (pre-commit hook installed)"
        fi
      '';
    };

  };
}
