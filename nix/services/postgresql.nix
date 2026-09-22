{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  postgresql = pkgs.postgresql_18;

  # Backups get dumps, never the live cluster. On ${persist} because / is tmpfs
  # and a dump does not belong in RAM.
  dumpDir = "${persist}/var/backups/postgresql";

  apps = config.mhnet.postgresql.apps;
  passwordApps = lib.filterAttrs (_: app: app.passwordFile != null) apps;

  # pg_hba.conf is first-match-wins and does NOT fall through to the next rule
  # when authentication fails. So for a given (database, user, transport) it is
  # either peer or password, never both.
  # peer apps emit no rule at all and fall through to the generic `local all
  # all peer` below.
  appRules = lib.concatStrings (
    lib.mapAttrsToList (
      name: app:
      lib.optionalString (app.passwordFile != null) (
        ''
          local ${name} ${name} scram-sha-256
        ''
        + lib.optionalString app.localhostTCP ''
          host  ${name} ${name} 127.0.0.1/32 scram-sha-256
          host  ${name} ${name} ::1/128      scram-sha-256
        ''
      )
    ) apps
  );

in
{
  options.mhnet.postgresql.apps = lib.mkOption {
    description = ''
      Per-app databases. The attribute name is the role, the database and the
      owner all at once — see docs/postgresql.md.
    '';
    default = { };
    example = lib.literalExpression ''
      {
        peerapp = { };
        webapp = {
          passwordFile = config.age.secrets.pg-webapp.path;
          localhostTCP = true;
        };
      }
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          passwordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Runtime path to a file holding the role's password, typically
              `config.age.secrets.<name>.path`. Null means peer auth only,
              which requires a system user of the same name.
            '';
          };

          localhostTCP = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Also accept password connections over 127.0.0.1 and ::1, for apps
              that only speak host:port. Requires {option}`passwordFile`.
            '';
          };
        };
      }
    );
  };

  config = {
    assertions = lib.mapAttrsToList (name: app: {
      assertion = app.localhostTCP -> app.passwordFile != null;
      message = "mhnet.postgresql.apps.${name}: localhostTCP needs a passwordFile, peer auth does not work over TCP.";
    }) apps;

    services.postgresql = {
      enable = true;
      package = postgresql;
      dataDir = "${persist}/var/lib/postgresql/${postgresql.psqlSchema}";
      extensions = ps: with ps; [ pg_repack ];

      # `ensureDBOwnership` asserts that a database of the same name exists in
      # `ensureDatabases`.
      ensureDatabases = lib.attrNames apps;
      ensureUsers = map (name: {
        inherit name;
        ensureDBOwnership = true;
      }) (lib.attrNames apps);

      # Only our own rules. Upstream appends its defaults with mkAfter, so an
      # unprefixed value lands above them and every app rule is matched first.
      authentication = appRules;

      settings = {
        # https://pgtune.leopard.in.ua/?dbVersion=18&osType=linux&dbType=web&cpuNum=24&totalMemory=32&totalMemoryUnit=GB&connectionNum=100&hdType=ssd
        # DB Version: 18
        # OS Type: linux
        # DB Type: web
        # Total Memory (RAM): 32 GB
        # CPUs num: 24
        # Connections num: 100
        # Data Storage: ssd
        max_connections = 100;
        shared_buffers = "8GB";
        effective_cache_size = "24GB";
        maintenance_work_mem = "2GB";
        checkpoint_completion_target = 0.9;
        wal_buffers = "16MB";
        default_statistics_target = 100;
        random_page_cost = 1.1;
        effective_io_concurrency = 200;
        work_mem = "67650kB";
        huge_pages = "try";
        min_wal_size = "1GB";
        max_wal_size = "4GB";
        max_worker_processes = 24;
        max_parallel_workers_per_gather = 4;
        max_parallel_workers = 24;
        max_parallel_maintenance_workers = 4;
      };
    };

    # dataDir is not created automatically if outside `/var/lib/postgresql`.
    # The parent is created too, mirroring upstream's `StateDirectory =
    # "postgresql postgresql/<schema>"`, so postgres can lay down a sibling
    # schema dir itself on a major-version upgrade.
    systemd.tmpfiles.settings."10-postgresql" =
      let
        dir = {
          d = {
            mode = "0750";
            user = "postgres";
            group = "postgres";
          };
        };
        dataDir = config.services.postgresql.dataDir;
      in
      {
        ${dirOf dataDir} = dir;
        ${dataDir} = dir;
        # root-owned: the pre-backup hook runs as root and redirects into it,
        # so postgres itself never needs write access here.
        ${dumpDir}.d = {
          mode = "0700";
          user = "root";
          group = "root";
        };
      };

    # Dumps every database plus the globals (roles, tablespaces), so app
    # modules need no hooks of their own. The dumps are under ${persist} and
    # thus already covered by mhnet.backup.paths.
    mhnet.backup = {
      # The whole parent, not just dataDir: a major-version upgrade leaves a
      # sibling schema dir behind and that is cluster data too.
      exclude = [ (dirOf config.services.postgresql.dataDir) ];
      prepare = ''
        rm -f ${dumpDir}/*.dump ${dumpDir}/globals.sql
        ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${config.services.postgresql.finalPackage}/bin/pg_dumpall --globals-only \
          > ${dumpDir}/globals.sql
        ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${config.services.postgresql.finalPackage}/bin/psql --no-align --tuples-only \
          --command 'SELECT datname FROM pg_database WHERE NOT datistemplate' \
          | while read -r db; do
              ${pkgs.util-linux}/bin/runuser -u postgres -- \
                ${config.services.postgresql.finalPackage}/bin/pg_dump --format=custom "$db" \
                > "${dumpDir}/$db.dump"
            done
      '';
    };

    # `ensureUsers` has no passwordFile and its only password knob,
    # `ensureClauses.password`, would put the password in the world-readable
    # nix store. So the password is applied out of band, idempotently, on every
    # boot and activation. Rotating a password is `agenix -e` plus `just
    # switch`.
    systemd.services = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "postgresql-password-${name}" {
        description = "Set the PostgreSQL password for ${name}";

        # postgresql-setup.service is upstream's oneshot that runs
        # ensureDatabases/ensureUsers, so the role exists by the time we run.
        # Ordering before postgresql.target means anything that waits for the
        # target sees a usable password.
        requires = [ "postgresql-setup.service" ];
        after = [ "postgresql-setup.service" ];
        before = [ "postgresql.target" ];
        wantedBy = [ "postgresql.target" ];

        path = [ config.services.postgresql.finalPackage ];
        environment.PGPORT = toString config.services.postgresql.settings.port;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Peer-matches `local all postgres peer map=postgres`.
          User = "postgres";
          Group = "postgres";
          # systemd reads the secret as root and hands it to the unit, so the
          # agenix secret can keep its default 0400 root:root.
          LoadCredential = "password:${app.passwordFile}";
        };

        # The password reaches psql through the environment and psql's own
        # \getenv, so it never appears in the nix store, the unit file or ps
        # output. :'pw' applies psql's literal quoting, so any character is
        # safe. (ALTER ROLE would show up in the server log if log_statement
        # were ever set to ddl or all; it is unset.)
        script = ''
          set -euo pipefail
          PG_APP_PASSWORD=$(< "$CREDENTIALS_DIRECTORY/password")
          export PG_APP_PASSWORD
          psql -d postgres -v ON_ERROR_STOP=1 --no-psqlrc -q <<'SQL'
          \getenv pw PG_APP_PASSWORD
          ALTER ROLE "${name}" PASSWORD :'pw';
          SQL
        '';
      }
    ) passwordApps;
  };
}
