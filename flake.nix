{
  description = "madping-cloud infrastructure — NixOS + Incus GitOps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Secrets management — enable when age keys are generated
    # sops-nix = {
    #   url = "github:Mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # Deployment tool (alternative to nixos-rebuild)
    # colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
  let
    system   = "x86_64-linux";
    pkgs     = nixpkgs.legacyPackages.${system};
    lib      = nixpkgs.lib;

    # Local helpers
    localLib = import ./lib { inherit lib; };

    # Common specialArgs passed to every nixosSystem
    commonArgs = { inherit inputs; };

  in {

    # ── NixOS Configurations ─────────────────────────────────────────────────
    #
    # workbench   — Incus container on Thor running OpenClaw
    # thor        — Bare-metal Incus host (future: full NixOS install)
    # zimaboard   — Low-power SBC (future)

    nixosConfigurations = {

      # OpenClaw container — primary workbench
      workbench = localLib.mkContainer {
        inherit nixpkgs system;
        hostModule  = ./hosts/thor/containers/openclaw.nix;
        specialArgs = commonArgs;
      };

      # Thor host config (for future full NixOS install on host)
      thor = localLib.mkSystem {
        inherit nixpkgs system;
        hostModule  = ./hosts/thor/default.nix;
        specialArgs = commonArgs;
      };

      # ZimaBoard (template — fill in when provisioning)
      zimaboard = localLib.mkSystem {
        inherit nixpkgs system;
        hostModule  = ./hosts/zimaboard/default.nix;
        specialArgs = commonArgs;
      };

    };

    # ── Dev Shell ─────────────────────────────────────────────────────────────
    # Enter with: nix develop
    devShells.${system}.default = pkgs.mkShell {
      name = "infra-dev";
      packages = with pkgs; [
        nixos-rebuild
        colmena
        git
        sops
        age
        jq
      ];
      shellHook = ''
        echo "🔧 madping-cloud infrastructure dev shell"
        echo "   nix flake check          — validate all configs"
        echo "   colmena apply            — deploy all hosts"
        echo "   ./deploy/scripts/deploy.sh workbench — deploy workbench"
      '';
    };

  };
}
