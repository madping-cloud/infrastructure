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


      # Atlas — primary assistant agent
      atlas = mkAgent {
        name       = "atlas";
        hostModule = ./hosts/atlas/default.nix;
      };

      # Aurora — companion agent (Connie)
      aurora = mkAgent {
        name       = "aurora";
        hostModule = ./hosts/aurora/default.nix;
      };

      # Mira — adult content agent
      mira = mkAgent {
        name       = "mira";
        hostModule = ./hosts/mira/default.nix;
      };

      # CSO — Chief Strategy Officer
      # Business discovery, competitive intelligence, strategic positioning.
      # Names itself on first run.
      cso = mkAgent {
        name       = "cso";
        hostModule = ./hosts/cso/default.nix;
      };

      # Lead Dev — Lead Developer
      # Technical feasibility, architecture, code review, dev standards.
      # Names itself on first run.
      leaddev = mkAgent {
        name       = "leaddev";
        hostModule = ./hosts/leaddev/default.nix;
      };

      # SIEM — Security Analyst
      # Monitors all agent activity, logs events, flags anomalies, Discord alerts.
      # Names itself on first run.
      siem = mkAgent {
        name       = "siem";
        hostModule = ./hosts/siem/default.nix;
      };

      # Dutch — Cannabis knowledge agent
      # Strain research, terpenes, cultivar recs, market intel. DeepSeek V3.2 primary.
      dutch = mkAgent {
        name       = "dutch";
        hostModule = ./hosts/dutch/default.nix;
      };

      # Harlan — Microsoft MXDR specialist
      # MXDR onboarding, Defender stack, Sentinel KQL, alert tuning. Anthropic-only.
      harlan = mkAgent {
        name       = "harlan";
        hostModule = ./hosts/harlan/default.nix;
      };

      # Rune — general-purpose agent with xAI integration
      rune = mkAgent {
        name       = "rune";
        hostModule = ./hosts/rune/default.nix;
      };
    };

    # ── Dev Shell ─────────────────────────────────────────────────────────────
    devShells.${system}.default = pkgs.mkShell {
      name = "infra-dev";
      packages = with pkgs; [ git sops age jq nixos-rebuild ];
      shellHook = ''
        echo "madping-cloud infrastructure"
        echo "   nixos-rebuild switch --flake .#cole    — rebuild cole"
        echo "   nixos-rebuild switch --flake .#atlas   — rebuild atlas"
        echo "   nixos-rebuild switch --flake .#aurora  — rebuild aurora"
        if [ -d .git ]; then
          ln -sf ../../scripts/pre-commit-check.sh .git/hooks/pre-commit
        fi
      '';
    };

  };
}
