{
  config,
  lib,
  ...
}:
let
  domain = "dms.mhnet.app";
  port = 7880;

  # Docspell uses JDBC which does not support peer auth, so the DB user
  # requires a password. The docspell config does not allow reading values from
  # other files, but we can overwrite settings via env vars.
  dbEnvFile = "/run/docspell-db-env/env";

  docspellUnits = [
    "docspell-restserver.service"
    "docspell-joex.service"
  ];

  jdbc = {
    url = "jdbc:postgresql://localhost/docspell?socket=/run/postgresql/.s.PGSQL.5432";
    user = "docspell";
  };
  full-text-search = {
    enabled = true;
    backend = "postgresql";
    postgresql.use-default-connection = true;
  };

  extraServiceConfig = {
    # https://github.com/lightbend/config?tab=readme-ov-file#optional-system-or-env-variable-overrides
    # Environment variables must be named `CONFIG_FORCE_docspell_...`
    Environment = "JAVA_OPTS=-Dconfig.override_with_env_vars=true";
    # Last file wins, so the rendered password always beats a stale one left in
    # the hand-edited secret.
    EnvironmentFile = [
      config.age.secrets.docspell-env.path
      dbEnvFile
    ];
    Restart = "always";
  };

  # The upstream module leaves User= unset and drops to the docspell user with
  # su(1) inside the script, so every sandbox setting below would wrap su
  # instead of the JVM. Rebuild its command (nix/modules/{server,joex}.nix) and
  # run it as the user from the start.
  mkExec =
    svc: exe:
    "${lib.getExe' svc.package exe} ${lib.escapeShellArgs svc.jvmArgs} -- ${
      if svc.configFile == null then "/etc/${exe}.conf" else "${svc.configFile}"
    }";

  hardening = {
    User = "docspell";
    Group = "docspell";

    NoNewPrivileges = true;
    # joex' converters write their scratch files here
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
    # JDBC over the postgresql socket, plus outbound SMTP and HTTP from joex.
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    LockPersonality = true;
    RemoveIPC = true;
    # An empty list would render no line at all and leave the default set.
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    SystemCallFilter = [ "@system-service" ];
    SystemCallErrorNumber = "EPERM";
    SystemCallArchitectures = "native";
    UMask = "0077";
    # No MemoryDenyWriteExecute: the JVM's JIT needs W+X pages.
    # The module's createHome=true home is on tmpfs and stays empty in
    # practice, but keep it writable so a stray JVM error dump behaves as
    # it does today.
    ReadWritePaths = [ "/var/docspell" ];
  };
in
{
  age.secrets = {
    docspell-env.file = ../secrets/docspell-env.age;
    # The DB password is in its own secret because it is used by the postgresql module.
    pg-docspell.file = ../secrets/pg-docspell.age;
  };

  mhnet.postgresql.apps.docspell.passwordFile = config.age.secrets.pg-docspell.path;
  mhnet.proxy.hosts.${domain}.upstream = "127.0.0.1:${toString port}";
  # A failed dependency does not put the dependent unit into the failed state,
  # so the renderer needs its own push.
  mhnet.notify.units = docspellUnits ++ [ "docspell-db-env.service" ];

  services.docspell-restserver = {
    enable = true;

    app-name = "mhnet Docspell";
    base-url = "https://${domain}";
    bind = {
      inherit port;
      address = "127.0.0.1";
    };

    inherit full-text-search;
    backend.jdbc = jdbc;
  };

  services.docspell-joex = {
    enable = true;
    inherit jdbc full-text-search;
  };

  systemd.services = {
    # postgresql.target is reached only after postgresql-password-docspell has
    # applied the password, so both services find a usable role.
    docspell-restserver = {
      after = [ "postgresql.target" ];
      script = lib.mkForce "exec ${mkExec config.services.docspell-restserver "docspell-restserver"}";
      serviceConfig = extraServiceConfig // hardening;
    };
    docspell-joex = {
      after = [ "postgresql.target" ];
      script = lib.mkForce "exec ${mkExec config.services.docspell-joex "docspell-joex"}";
      serviceConfig = extraServiceConfig // hardening;
    };

    # A LibreOffice listener that only speeds up office-format conversion —
    # unused here, since nothing but PDFs is uploaded. It cannot work anyway:
    # unoconv 0.9.0 calls LooseVersion from the long-removed distutils, so it
    # dies on LibreOffice's Python 3.13 before it ever launches soffice.
    unoconv.enable = false;

    docspell-db-env = {
      description = "Render docspell's database password into an environment file";
      requiredBy = docspellUnits;
      before = docspellUnits;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "docspell-db-env";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        # systemd reads the secret as root and hands it to the unit, so the
        # agenix secret keeps its default 0400 root:root — as does the file
        # written here, since EnvironmentFile= is read by the service manager.
        LoadCredential = "password:${config.age.secrets.pg-docspell.path}";
      };

      script = ''
        password=$(< "$CREDENTIALS_DIRECTORY/password")
        # Single quotes are systemd's only escape-free quoting, so a password
        # containing one would be silently mangled. Fail loudly instead.
        case $password in
          *"'"*)
            echo "the docspell database password must not contain a single quote" >&2
            exit 1
            ;;
        esac
        printf "%s='%s'\n%s='%s'\n" \
          CONFIG_FORCE_docspell_server_backend_jdbc_password "$password" \
          CONFIG_FORCE_docspell_joex_jdbc_password "$password" \
          > ${dbEnvFile}
      '';
    };
  };
}
