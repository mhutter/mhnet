{ config, lib, ... }:
let
  host = "feeds.mhnet.app";
  socketPath = "/run/miniflux/miniflux.sock";

in
{
  age.secrets.minifluxEnv.file = ../secrets/miniflux-env.age;
  mhnet.proxy.hosts."${host}".upstream = "unix/${socketPath}";
  mhnet.notify.units = [ "miniflux.service" ];
  # DB created by the services.miniflux module

  # unix(7): SOCK_STREAM connect() requires write permission on the socket
  users.users.caddy.extraGroups = [ "miniflux" ];

  # The upstream module uses DynamicUser, whose GID only exists at runtime and
  # so cannot be handed to Caddy. A static user and group can.
  users.users.miniflux = {
    isSystemUser = true;
    group = "miniflux";
  };
  users.groups.miniflux = { };

  systemd.services.miniflux.serviceConfig = {
    DynamicUser = lib.mkForce false;
    # Upstream's 0077 would leave the socket 0700, closed to Caddy's group.
    UMask = lib.mkForce "0007";
  };

  services.miniflux = {
    enable = true;

    config = rec {
      BASE_URL = "https://${host}";
      LISTEN_ADDR = socketPath;
      HTTPS = 1;
      CREATE_ADMIN = 0;

      OAUTH2_PROVIDER = "oidc";
      OAUTH2_REDIRECT_URL = "${BASE_URL}/oauth2/oidc/callback";
      OAUTH2_USER_CREATION = 1;
      OAUTH2_OIDC_PROVIDER_NAME = "mhnet ID";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://id.mhnet.app";
      DISABLE_LOCAL_AUTH = 1;
    };

    # It's called "adminCredentialsFile", but it's just used as
    # `EnvironmentFile=` in the systemd service, so we can use it to inject
    # _any_ sensitive env vars
    adminCredentialsFile = config.age.secrets.minifluxEnv.path;
  };
}
