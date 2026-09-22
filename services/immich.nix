{
  config,
  pkgs,
  persist,
  ...
}:
let
  host = "immich.mhnet.app";
  dataDir = "${persist}/var/lib/immich";

  cfg = config.services.immich;
in
{
  age.secrets.immichOauthClientSecret.file = ../secrets/immich-oauth-client-secret.age;
  mhnet.proxy.hosts.${host}.upstream = "127.0.0.1:${toString cfg.port}";
  mhnet.notify.units = [
    "immich-machine-learning.service"
    "immich-server.service"
    "redis-immich.service"
  ];
  systemd.tmpfiles.rules = [ "d ${dataDir} 0700 ${cfg.user} ${cfg.group}" ];
  systemd.services.immich-server.serviceConfig.RequiresMountsFor = dataDir;

  services.immich = {
    enable = true;
    package = pkgs.unstable.immich;
    host = "127.0.0.1";

    settings = {
      server.externalDomain = "https://${host}";

      oauth = {
        enabled = true;
        issuerUrl = "https://id.mhnet.app/";
        clientId = "c27ab67a-2e03-45d7-b6b3-522b48f32062";
        buttonText = "Login with mhnet ID";
        clientSecret._secret = config.age.secrets.immichOauthClientSecret.path;
      };
      passwordLogin.enabled = false;
    };

    mediaLocation = dataDir;
  };
}
