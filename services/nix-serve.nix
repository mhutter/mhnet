{ config, ... }:
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
  };
}
