{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  mysql = config.services.mysql.package;
  runuser = "${pkgs.util-linux}/bin/runuser";

  # Backups get dumps, never the live datadir. On ${persist} because / is tmpfs
  # and a dump does not belong in RAM.
  dumpDir = "${persist}/var/backups/mysql";
in
{
  # Enabled by whichever service needs it (currently services/azerothcore.nix);
  # this only shapes the server once it is.
  config = lib.mkIf config.services.mysql.enable {
    services.mysql = {
      dataDir = "${persist}/var/lib/mysql";

      # Tuned for mod-playerbots' write load, see
      # https://github.com/mod-playerbots/mod-playerbots/wiki/Playerbot-Configuration
      # Wiki values that 8.4 already defaults to (innodb_use_fdatasync, auto
      # buffer_pool_instances, a larger log buffer) are left out.
      settings.mysqld = {
        ## Durability traded for fewer writes
        skip-log-bin = true; # no replication, restores come from the dumps
        innodb_flush_log_at_trx_commit = 2; # an OS crash loses ≤1s, a mysqld crash nothing

        ## Memory
        # Not the wiki's 50% of RAM: that assumes a dedicated box, the data is
        # a few GB and the host is shared.
        innodb_buffer_pool_size = "8G";
        performance_schema = false; # a few hundred MB nobody reads

        ## Write smoothing
        innodb_redo_log_capacity = "2G"; # 8.4 default 100M, too small for bursty bot saves
        innodb_io_capacity = 500; # below 8.4's 10000: less background flushing, less NVMe wear
        innodb_io_capacity_max = 2500;

        transaction_isolation = "READ-COMMITTED"; # wiki: fewer deadlocks

        # Clients connect via /run/mysqld/mysqld.sock only.
        skip_networking = true;
      };
    };

    # --initialize-insecure leaves root@localhost without a password, and
    # upstream only fixes that from stateVersion 26.11 on. Idempotent; runs as
    # the mysql user, which upstream creates with auth_socket and ALL WITH
    # GRANT OPTION.
    systemd.services.mysql.postStart = lib.mkAfter ''
      echo "ALTER USER root@localhost IDENTIFIED WITH auth_socket;" | ${mysql}/bin/mysql -N
    '';

    # root-owned: the pre-backup hook runs as root and redirects into it, so
    # mysql itself never needs write access here.
    systemd.tmpfiles.settings."10-mysql".${dumpDir}.d = {
      mode = "0700";
      user = "root";
      group = "root";
    };

    # One dump per database. Users and grants are not dumped: they are all
    # auth_socket and recreated by ensureUsers. --single-transaction gives a
    # consistent InnoDB snapshot without locking out the worldserver.
    mhnet.backup = {
      exclude = [ config.services.mysql.dataDir ];
      prepare = ''
        rm -f ${dumpDir}/*.sql
        ${runuser} -u mysql -- ${mysql}/bin/mysql --batch --skip-column-names \
          --execute 'SHOW DATABASES' \
          | { ${pkgs.gnugrep}/bin/grep -vxE 'mysql|sys|information_schema|performance_schema' || true; } \
          | while read -r db; do
              ${runuser} -u mysql -- ${mysql}/bin/mysqldump \
                --single-transaction --routines --events --triggers \
                --databases "$db" \
                > "${dumpDir}/$db.sql"
            done
      '';
    };
  };
}
