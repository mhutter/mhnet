{ ... }:
{
  imports = [
    ./boot.nix
    ./configuration.nix
    ./disks.nix
    ./network.nix
    ./openssh.nix
    ./persistence.nix
    ./users.nix
    ./nix.nix
  ];
}
