{ config, pkgs, ... }:
let
  cfg = config.services.nix-serve;
in
{

  age.secrets.nixServeSecretKey.file = ../secrets/nix-serve-secret-key.age;
  mhnet.proxy.hosts."cache.mhnet.app".upstream = "127.0.0.1:${toString cfg.port}";
  services.nix-serve = {
    enable = true;
    bindAddress = "127.0.0.1";
    secretKeyFile = config.age.secrets.nixServeSecretKey.path;
    # upstream hardcodes "Priority: 30" in nix-serve.psgi, no option to configure it
    package = pkgs.nix-serve.overrideAttrs (old: {
      postPatch = ''
        ${old.postPatch or ""}
        substituteInPlace nix-serve.psgi --replace-fail 'Priority: 30' 'Priority: 50'
      '';
    });
  };
}
