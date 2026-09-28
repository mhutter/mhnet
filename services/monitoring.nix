## Monitoring hub: VictoriaMetrics (metrics), VictoriaLogs (logs), Grafana (UI)
{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  metricsHost = "metrics.mhnet.app";
  logsHost = "logs.mhnet.app";

  # Basic auth credentials for metrics/log ingestion.
  # Shared with ansible/roles/monitoring_agent (monitoring_remote_write_user).
  user = "monitoring";
  passwordFile = config.age.secrets.monitoring-password.path;

  vmPort = 8428;
  vlPort = 9428;
  vmDataDir = "${persist}/var/lib/victoriametrics";
  vlDataDir = "${persist}/var/lib/victorialogs";

  grafanaHost = "grafana.mhnet.app";
  grafanaPort = 3000;
  grafanaDataDir = "${persist}/var/lib/grafana";
  grafanaDumpDir = "${persist}/var/backups/grafana";

  # The upstream modules run with DynamicUser and keep their data in a
  # StateDirectory under /var/lib, which is tmpfs here. A static user can own a
  # directory on ${persist}; the later -storageDataPath wins over the module's
  # hardcoded one (Go's flag package keeps the last value).
  persistent = name: dataDir: {
    unitConfig.RequiresMountsFor = dataDir;
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = name;
      Group = name;
      StateDirectory = lib.mkForce "";
      ReadWritePaths = [ dataDir ];
      # DynamicUser implied strict; without it the module's "full" would leave
      # all of ${persist} writable.
      ProtectSystem = lib.mkForce "strict";
    };
  };

  staticUser = name: {
    users.${name} = {
      isSystemUser = true;
      group = name;
    };
    groups.${name} = { };
  };
in
{
  age.secrets = {
    # Grafana reads it too, for the datasources.
    monitoring-password = {
      file = ../secrets/monitoring-password.age;
      group = "grafana";
      mode = "0440";
    };
    # Must be the key grafana.db was created with, or every secret stored in
    # it (datasource passwords, the Telegram bot token) fails to decrypt.
    grafana-secret-key = {
      file = ../secrets/grafana-secret-key.age;
      owner = "grafana";
    };
  };

  # Native basic auth stays on the daemons, Caddy only adds TLS: the Grafana
  # datasources and both agent pieces already send the credential. Access logs
  # off: vmagent pushes every few seconds and journal-upload streams
  # continuously, per host.
  mhnet.proxy.hosts = {
    ${metricsHost} = {
      upstream = "127.0.0.1:${toString vmPort}";
      log = false;
    };
    ${logsHost} = {
      upstream = "127.0.0.1:${toString vlPort}";
      log = false;
    };
    ${grafanaHost}.upstream = "127.0.0.1:${toString grafanaPort}";
  };

  mhnet.notify.units = [
    "victoriametrics.service"
    "victorialogs.service"
    "grafana.service"
  ];

  users = lib.mkMerge [
    (staticUser "victoriametrics")
    (staticUser "victorialogs")
  ];

  systemd.tmpfiles.rules = [
    "d ${vmDataDir} 0700 victoriametrics victoriametrics -"
    "d ${vlDataDir} 0700 victorialogs victorialogs -"
    "d ${grafanaDumpDir} 0700 root root -"
  ];

  services.victoriametrics = {
    enable = true;
    # Loopback only, so no -enableTCP6: Caddy is the public listener.
    listenAddress = "127.0.0.1:${toString vmPort}";
    retentionPeriod = "12"; # months
    basicAuthUsername = user;
    basicAuthPasswordFile = passwordFile;
    extraOptions = [ "-storageDataPath=${vmDataDir}" ];
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:${toString vlPort}";
    basicAuthUsername = user;
    basicAuthPasswordFile = passwordFile;
    extraOptions = [
      "-storageDataPath=${vlDataDir}"
      "-retentionPeriod=90d"
    ];
  };

  systemd.services.victoriametrics = persistent "victoriametrics" vmDataDir;
  systemd.services.victorialogs = persistent "victorialogs" vlDataDir;

  # Migrated from the Ansible hub by copying its grafana.db (docs/monitoring.md),
  # so users, contact points and notification policies come along; everything
  # below is re-provisioned on top on every start.
  services.grafana = {
    enable = true;
    # Closest to the Ansible hub's apt Grafana (>= 13.2), whose db this opens;
    # nixos-26.05 has 13.0.
    package = pkgs.unstable.grafana;
    # The users.users.grafana home, created on activation.
    dataDir = grafanaDataDir;

    # Core datasources (prometheus backs VictoriaMetrics) are built in; only
    # the VictoriaLogs one is a plugin. Declarative plugins also turn off
    # Grafana's background installer and its plugin update checks.
    declarativePlugins = [ pkgs.unstable.grafanaPlugins.victoriametrics-logs-datasource ];

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        domain = grafanaHost;
        # Links in alert notifications point here instead of localhost:3000.
        root_url = "https://${grafanaHost}";
      };
      security = {
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
        cookie_secure = true;
        # The admin comes with grafana.db. Should Grafana start before the
        # copy, it must not create an admin/admin account on a public host.
        disable_initial_admin_creation = true;
      };
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      # The journal is enough; the default also writes ${grafanaDataDir}/log.
      log.mode = "console";
    };

    provision = {
      enable = true;
      # Same names and uids as on the Ansible hub, which dashboards and alert
      # rules reference. Loopback, so no TLS; the credential stays out of the
      # nix store through Grafana's file provider.
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "VictoriaMetrics";
            uid = "victoriametrics";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:${toString vmPort}";
            isDefault = true;
            basicAuth = true;
            basicAuthUser = user;
            secureJsonData.basicAuthPassword = "$__file{${passwordFile}}";
            # monitoring_scrape_interval of the agents.
            jsonData.timeInterval = "30s";
          }
          {
            name = "VictoriaLogs";
            uid = "victorialogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://127.0.0.1:${toString vlPort}";
            basicAuth = true;
            basicAuthUser = user;
            secureJsonData.basicAuthPassword = "$__file{${passwordFile}}";
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "mhnet";
            type = "file";
            options.path = ./monitoring/dashboards;
          }
        ];
      };
      # Alert rules and the Telegram template; contact points and policies
      # stay UI-managed (in grafana.db).
      alerting.rules.path = ./monitoring/grafana-alerting.yml;
    };
  };

  systemd.services.grafana = {
    unitConfig.RequiresMountsFor = grafanaDataDir;
    serviceConfig = {
      ReadWritePaths = [ grafanaDataDir ];
      # The module's "full" would leave all of ${persist} writable.
      ProtectSystem = lib.mkForce "strict";
    };
  };

  # restic gets a hardlink snapshot of the TSDB, never the live one. Only the
  # fresh snapshot is kept; it costs nothing beyond blocks compacted away until
  # the next run. Unlike the Ansible hook a failed snapshot aborts the backup,
  # as every mhnet.backup.prepare hook does. The credential goes through
  # --config, keeping it out of curl's argv.
  #
  # VictoriaLogs has no snapshot mechanism and its data is the least critical;
  # it is deliberately not backed up.
  #
  # Grafana's SQLite db is dumped with VACUUM INTO instead of copied live --
  # read-only, so a db not yet migrated over is skipped rather than created.
  # VACUUM INTO refuses to overwrite, hence the rm; the timeout rides out
  # concurrent write transactions.
  mhnet.backup = {
    exclude = [
      "${vmDataDir}/data"
      "${vmDataDir}/indexdb"
      "${vmDataDir}/cache"
      vlDataDir
      "${grafanaDataDir}/data/grafana.db*"
    ];
    prepare = ''
      victoriametrics_snapshot() {
        ${pkgs.curl}/bin/curl -fsS -X POST \
          "http://127.0.0.1:${toString vmPort}/snapshot/$1" \
          --config <(printf 'user = "%s:%s"\n' ${user} "$(< ${passwordFile})") \
          > /dev/null
      }
      victoriametrics_snapshot delete_all
      victoriametrics_snapshot create

      rm -f ${grafanaDumpDir}/grafana.db
      if [ -e ${config.services.grafana.settings.database.path} ]; then
        ${pkgs.sqlite}/bin/sqlite3 -readonly -cmd '.timeout 5000' \
          ${config.services.grafana.settings.database.path} \
          "VACUUM INTO '${grafanaDumpDir}/grafana.db'"
      fi
    '';
  };
}
