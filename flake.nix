{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The game sources are pinned here rather than in the module's own lock, so
    # updating them is a lock bump in this repo. Like everything AzerothCore,
    # they are left out of the weekly bump (update-lock.yml): new commits
    # bring schema changes the worldserver applies to the databases on start.
    azerothcore = {
      url = "github:mhutter/azerothcore-playerbots-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.azerothcore-src.follows = "azerothcore-src";
      inputs.mod-playerbots-src.follows = "mod-playerbots-src";
    };
    # The two move in lockstep, as the mod-playerbots wiki demands.
    azerothcore-src = {
      url = "github:mod-playerbots/azerothcore-wotlk/Playerbot";
      flake = false;
    };
    mod-playerbots-src = {
      url = "github:mod-playerbots/mod-playerbots/master";
      flake = false;
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

    ### Azerothcore Mods
    mod-ah-bot-plus = {
      url = "github:NathanHandley/mod-ah-bot-plus";
      flake = false;
    };
    mod-individual-progression = {
      url = "github:ZhengPeiRu21/mod-individual-progression";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      agenix,
      azerothcore,
      azerothcore-src,
      mod-playerbots-src,
      disko,
      docspell,
      impermanence,
      mod-ah-bot-plus,
      mod-individual-progression,
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
          # Sources compiled into the worldserver: services.azerothcore.extraModules
          azerothcoreModules = { inherit mod-ah-bot-plus mod-individual-progression; };
        };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
