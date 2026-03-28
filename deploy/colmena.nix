# deploy/colmena.nix — Colmena deployment config
#
# Deploy with:
#   colmena apply --on workbench
#   colmena apply --all
#
# Colmena reads this file to know where each host lives and what config to push.
# It's separate from flake.nix nixosConfigurations to allow deploy-specific overrides.

{
  meta = {
    nixpkgs = import <nixpkgs> { system = "x86_64-linux"; };
    description = "madping-cloud Colmena deployment";
  };

  # OpenClaw workbench container on Thor
  workbench = { name, nodes, pkgs, ... }: {
    deployment = {
      targetHost = "10.100.0.21";
      targetUser = "root";
      allowLocalDeployment = false;
      tags = [ "container" "openclaw" "thor" ];
    };

    imports = [
      ../hosts/thor/containers/openclaw.nix
    ];
  };

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
