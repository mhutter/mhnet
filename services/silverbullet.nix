{
  config,
  pkgs,
  persist,
  ...
}:
let
  host = "lm22.mhnet.app";
  dataDir = "${persist}/var/lib/silverbullet";
  socketPath = "/run/silverbullet/silverbullet.sock";

  cfg = config.services.silverbullet;
in
{
  age.secrets.silverbullet-env.file = ../secrets/silverbullet-env.age;

  mhnet.proxy.hosts.${host}.upstream = "unix/${socketPath}";
  mhnet.notify.units = [ "silverbullet.service" ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 ${cfg.user} ${cfg.group} -"
  ];

  # unix(7): SOCK_STREAM connect() requires write permission on the socket
  users.users.caddy.extraGroups = [ cfg.group ];

  services.silverbullet = {
    enable = true;
    # nixos-26.05 has 2.6.1, which predates SB_UNIX_SOCKET support.
    package = pkgs.unstable.silverbullet;
    spaceDir = dataDir;
    envFile = config.age.secrets.silverbullet-env.path;
  };

  systemd.services.silverbullet = {
    unitConfig.RequiresMountsFor = dataDir;

    environment = {
      # Wins over the module's hardcoded --port/--hostname flags
      SB_UNIX_SOCKET = socketPath;
      # Plugs can otherwise run shell commands as the service user.
      SB_SHELL_BACKEND = "off";
      SB_INDEX_PAGE = "Langmoos 22a";
    };

    serviceConfig = {
      RuntimeDirectory = "silverbullet";
      RuntimeDirectoryMode = "0750";
      # Affects the socket file's mode too, not just newly written notes:
      # 0007 makes the socket group-writable for Caddy without widening it to
      # "other".
      UMask = "0007";

      # The upstream module ships no hardening at all.
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
      ReadWritePaths = [ dataDir ];
      # Unix socket only -- no TCP listener, unlike the old ansible unit
      # which also exposed a metrics port.
      RestrictAddressFamilies = [ "AF_UNIX" ];
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
