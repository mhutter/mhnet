{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShell."${system}" = pkgs.mkShell {
        packages = with pkgs; [
          ansible
          apt-dater
        ];

        APT_DATER_DTD_ROOT = "${pkgs.apt-dater}/share/xml/schema/apt-dater";
      };
    };
}
