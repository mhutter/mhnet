{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  cfg = config.mhnet.backup;
  host = config.networking.hostName;

  # The repository path MUST equal the B2 application key's file name prefix
  # ("<hostname>/", see docs/backup.md). Renaming the host breaks access to the
  # existing repository.
  repository = "s3:${cfg.s3Endpoint}/${cfg.bucket}/${host}";

  retention = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 12"
    "--keep-yearly 10"
  ];

  common = {
    inherit repository;
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-env.path;
  };

  jobs = [
    host
    "${host}-prune"
  ];
in
{
  options.mhnet.backup = {
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up. Service modules append their own — see docs/backup.md.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Exclude patterns, applied to {option}`paths`.";
    };

    prepare = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Shell run before the backup, as root. Lines from all modules are
        concatenated and run under `set -euo pipefail`, so a failing hook aborts
        the backup instead of silently shipping a stale dump.
      '';
    };

    s3Endpoint = lib.mkOption {
      type = lib.types.str;
      default = "s3.eu-central-003.backblazeb2.com";
      description = "S3 endpoint of the Backblaze B2 region holding {option}`bucket`.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "mhnet-restic";
      description = "B2 bucket, shared with the mhnet fleet — one prefix per host.";
    };
  };

  config = {
    age.secrets = {
      restic-password.file = ../secrets/restic-password.age;
      restic-env.file = ../secrets/restic-env.age;
    };

    # / is tmpfs, so everything worth keeping is already under ${persist} —
    # minus the journal, the persisted caches and the live PGDATA (dumped
    # instead, see services/postgresql.nix).
    mhnet.backup = {
      paths = [ persist ];
      exclude = [
        "${persist}/var/log"
        "${persist}/var/cache"
      ];
    };

    # Until now a backup that stopped working was silent, and would only have
    # surfaced at restore time.
    mhnet.notify.units = map (name: "restic-backups-${name}.service") jobs;

    services.restic.backups = {
      # Daily: prepare hooks, then backup. No forget/prune here — that is the
      # weekly job below, so a slow prune never delays a backup.
      ${host} = common // {
        inherit (cfg) paths exclude;
        initialize = true;
        # Shebang included: the module writes this out and executes it directly.
        backupPrepareCommand =
          if cfg.prepare == "" then
            null
          else
            ''
              #!${pkgs.runtimeShell}
              set -euo pipefail
            ''
            + cfg.prepare;
        extraBackupArgs = [ "--exclude-caches" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:30:00";
          Persistent = true;
        };
      };

      # Weekly: a paths-less entry, which the restic module turns into a
      # prune-only job (forget --prune, then check). An hour after the daily
      # backup; restic's repository lock is what actually keeps them apart.
      "${host}-prune" = common // {
        paths = [ ];
        # Group by host only, not the default host+paths: snapshots taken before
        # a path-set change then age out normally instead of being kept forever.
        pruneOpts = retention ++ [ "--group-by host" ];
        runCheck = true;
        createWrapper = false;
        timerConfig = {
          OnCalendar = "Sun *-*-* 04:30:00";
          Persistent = true;
        };
      };
    };

    # The module hardcodes the cache to /var/cache, which is tmpfs here: the
    # cache would die on every reboot and the next run would re-fetch the
    # repository index from B2. Move it to ${persist} instead (restic creates
    # the directory itself, 0700). CacheDirectory= is emptied, which resets
    # systemd's list, or it would keep making the unused /var/cache entry.
    # The restic-${host} wrapper reads this environment, so it follows along.
    systemd.services = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "restic-backups-${name}" {
          environment.RESTIC_CACHE_DIR = lib.mkForce "${persist}/var/cache/restic-backups-${name}";
          serviceConfig.CacheDirectory = lib.mkForce "";
        }
      ) jobs
    );
  };
}
