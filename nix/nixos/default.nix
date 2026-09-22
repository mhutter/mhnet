{ ... }:
{
  imports = [
    ## NixOS configuration
    ./boot.nix
    ./configuration.nix
    ./disks.nix
    ./network.nix
    ./openssh.nix
    ./persistence.nix
    ./users.nix
    ./nix.nix

    ## Modules
    ../modules/backup.nix

    ## Services
    ../services/postgresql.nix
    ../services/tailscale.nix
  ];
}
