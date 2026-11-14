{ config, persist, ... }:
let
  name = "kx-data";
  host = "kx-data.mhnet.app";
  # The app's default (127.0.0.1:3000) is taken by Grafana.
  listenAddr = "127.0.0.1:3010";

  # The binary is NOT part of the system closure: it changes several times a
  # day, so deploys swap this profile and restart the unit instead of
  # rebuilding the system — docs/kx-data.md. Under /nix, so it survives the
  # tmpfs root, and every generation is a GC root until nix-gc ages it out.
  profile = "/nix/var/nix/profiles/${name}";

  # / is tmpfs. Under ${persist}, so mhnet.backup picks it up with no hook.
  dataDir = "${persist}/var/lib/${name}";
in
{
  age.secrets.kx-data-env.file = ../secrets/kx-data-env.age;

  mhnet.proxy.hosts.${host}.upstream = listenAddr;
  mhnet.notify.units = [ "${name}.service" ];

  # Static, not DynamicUser: the data directory needs an owner that stays the
  # same across restarts. The UID is pinned in /var/lib/nixos, which persists.
  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };
  users.groups.${name} = { };

  systemd.tmpfiles.settings.${name}.${dataDir}.d = {
    mode = "0700";
    user = name;
    group = name;
  };

  systemd.services.${name} = {
    description = "kx-data";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # Skipped, not failed, until the first deploy has populated the profile.
    unitConfig = {
      ConditionPathExists = "${profile}/bin/${name}";
      RequiresMountsFor = dataDir;
    };

    environment = {
      RUST_LOG = "kx_data=debug,info";
      LISTEN_ADDR = listenAddr;
      MCP_ALLOWED_HOSTS = host;
      KX_DATA_DIR = dataDir;
    };

    serviceConfig = {
      ExecStart = "${profile}/bin/${name}";
      # KX_OWNER_HASH. Read by PID 1 before dropping privileges, so the
      # root-only secret needs no group juggling.
      EnvironmentFile = config.age.secrets.kx-data-env.path;
      Restart = "on-failure";
      RestartSec = "5s";

      User = name;
      Group = name;
      UMask = "0077";
      ReadWritePaths = [ dataDir ];

      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      RemoveIPC = true;
      MemoryDenyWriteExecute = true;
      # An empty list would render no line at all and leave the default set.
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      SystemCallFilter = [ "@system-service" ];
      SystemCallErrorNumber = "EPERM";
    };
  };
}
