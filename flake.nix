{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "";
      inputs.darwin.follows = "";
    };

    azerothcore = {
      url = "github:mhutter/azerothcore-playerbots-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    docspell = {
      url = "github:eikek/docspell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.devshell-tools.follows = "";
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
      nixpkgs-unstable,
      agenix,
      azerothcore,
      disko,
      docspell,
      impermanence,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;

        overlays = [
          docspell.overlays.default
          (final: prev: {
            unstable = import nixpkgs-unstable { inherit system; };
          })
        ];
        ## Add allowed "unfree" packages here
        # config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getname pkg) [ ];
      };

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          agenix.packages.${system}.default
          pkgs.apt-dater
        ];

        # apt-dater validates hosts.xml against a DTD it ships; the generator
        # (ansible/playbooks/apt-dater.yml) reads this to write the DOCTYPE.
        APT_DATER_DTD_ROOT = "${pkgs.apt-dater}/share/xml/schema/apt-dater";
      };

      nixosConfigurations.rhea = nixpkgs.lib.nixosSystem {
        inherit pkgs system;

        modules = [
          ./nixos
          agenix.nixosModules.default
          azerothcore.nixosModules.default
          disko.nixosModules.disko
          docspell.nixosModules.default
          impermanence.nixosModules.default
        ];

        specialArgs = {
          username = "mh";
          sshPublicKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENf5523OeX3ZEOJuAF9P5OLy+/S78UX7+xNC+O6AoD9" # mh@rotz2026
          ];
          persist = "/nix/persist";
        };
      };
    };
}
