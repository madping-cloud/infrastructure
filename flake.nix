{
  description = "Thor infrastructure — NixOS configs managed via GitOps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Secrets management (uncomment when ready to configure)
    # sops-nix = {
    #   url = "github:Mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, ... } @ inputs:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in
  {
    # NixOS system configurations
    nixosConfigurations = {
      workbench = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./nixos/hosts/workbench/configuration.nix
        ];
      };
    };

    # Development shell for working on this repo
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        nixos-rebuild
        git
        sops
        age
      ];
    };
  };
}
