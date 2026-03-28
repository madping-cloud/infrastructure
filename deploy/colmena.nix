# deploy/colmena.nix — Colmena deployment config
#
# Deploy with:
#   colmena apply --on silas
#   colmena apply --all
#
# Colmena reads this file to know where each host lives and what config to push.
# It's separate from flake.nix nixosConfigurations to allow deploy-specific overrides.
#
# MIGRATION NOTE: The old `workbench` entry has been removed. The repo has moved
# to named agents (silas, aurora, atlas). Add entries below to match the
# nixosConfigurations in flake.nix.

{
  meta = {
    nixpkgs = import <nixpkgs> { system = "x86_64-linux"; };
    description = "madping-cloud Colmena deployment";
  };

  # Silas — executor/craftsman agent (Marc's second brain)
  # silas = { name, nodes, pkgs, ... }: {
  #   deployment = {
  #     targetHost = "UNCONFIGURED";  # Set to silas container IP
  #     targetUser = "root";
  #     allowLocalDeployment = false;
  #     tags = [ "container" "openclaw" "agent" ];
  #   };
  #   imports = [ ../hosts/silas/default.nix ];
  # };

  # Aurora — Connie's companion agent
  # aurora = { name, nodes, pkgs, ... }: {
  #   deployment = {
  #     targetHost = "UNCONFIGURED";  # Set to aurora container IP
  #     targetUser = "root";
  #     allowLocalDeployment = false;
  #     tags = [ "container" "openclaw" "agent" ];
  #   };
  #   imports = [ ../hosts/aurora/default.nix ];
  # };

  # Atlas — Marc's primary assistant
  # atlas = { name, nodes, pkgs, ... }: {
  #   deployment = {
  #     targetHost = "UNCONFIGURED";  # Set to atlas container IP
  #     targetUser = "root";
  #     allowLocalDeployment = false;
  #     tags = [ "container" "openclaw" "agent" ];
  #   };
  #   imports = [ ../hosts/atlas/default.nix ];
  # };

  # Thor host (uncomment when running full NixOS on Thor)
  # thor = { name, nodes, pkgs, ... }: {
  #   deployment = {
  #     targetHost = "10.100.0.1";
  #     targetUser = "root";
  #     tags = [ "host" "incus" ];
  #   };
  #   imports = [ ../hosts/thor/default.nix ];
  # };
}
