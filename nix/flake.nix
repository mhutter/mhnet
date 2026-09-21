{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "";
      inputs.darwin.follows = "";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.home-manager.follows = "";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      disko,
      impermanence,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells."${system}".default = pkgs.mkShell {
        packages = [ agenix.packages.${system}.default ];
      };

      nixosConfigurations.rhea = nixpkgs.lib.nixosSystem {
        inherit system;

        pkgs = import nixpkgs {
          inherit system;

          ## Add allowed "unfree" packages here
          # config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getname pkg) [ ];
        };

        modules = [
          ./nixos
          agenix.nixosModules.default
          disko.nixosModules.disko
          impermanence.nixosModules.default
        ];

        specialArgs = {
          username = "mh";
          sshPublicKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENf5523OeX3ZEOJuAF9P5OLy+/S78UX7+xNC+O6AoD9" # mh@rotz2026
          ];
          persist = "/nix/persist";
          secrets = import ./secrets.nix "rhea";
        };
      };
    };
}
