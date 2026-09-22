{ ... }:
{
  imports = [
    ## NixOS configuration
    ./auto-upgrade.nix
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
    ../modules/notify.nix
    ../modules/proxy.nix

    ## Services
    ../services/docspell.nix
    ../services/immich.nix
    ../services/postgresql.nix
    ../services/silverbullet.nix
    ../services/tailscale.nix
  ];
}
