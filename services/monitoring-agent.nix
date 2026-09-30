## Monitoring agent: node_exporter scraped by Vector, pushed to VictoriaMetrics
#
# The NixOS counterpart of ansible/roles/monitoring_agent, metrics only. The
# hub runs on this host (services/monitoring.nix), so Vector writes to it on
# loopback: no TLS, and no disk buffer for hub outages.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = config.networking.hostName;
  nodePort = config.services.prometheus.exporters.node.port;
  vm = config.services.victoriametrics;
  textfileDir = "/var/lib/prometheus-node-exporter";

  # Bind mounts report the usage of the filesystem behind them (/nix/persist
  # on /nix), so each would chart as a duplicate of it. The mount points come
  # from impermanence, plus the read-only /nix/store bind NixOS sets up itself.
  bindMounts = [
    "/nix/store"
  ]
  ++ lib.concatMap (
    p: map (d: d.dirPath) p.directories ++ map (f: f.filePath) p.files
  ) (lib.attrValues config.environment.persistence);
  bindExclude = "(${lib.concatMapStringsSep "|" lib.escapeRegex bindMounts})$";

  # Of the tmpfs mounts only / is of interest; /run holds sockets, PID files and
  # secrets, and tmpfs usage shows up as memory anyway. ramfs always reports 0.
  runExclude = "/run($|/)";

  # Both flags replace node_exporter's defaults, so those are kept first.
  defaultMountExclude = "/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($|/)";
  defaultTypesExclude = "autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|erofs|sysfs|tracefs";
  mountPointsExclude = "^(${defaultMountExclude}|${runExclude}|${bindExclude})";
  fsTypesExclude = "^(${defaultTypesExclude}|ramfs)$";
in
{
  mhnet.notify.units = [
    "prometheus-node-exporter.service"
    "vector.service"
  ];

  # Same allowlist as monitoring_agent_enabled_collectors; its defaults explain
  # the choice. The module adds --collector.<name> for each.
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    enabledCollectors = [
      "cpu"
      "diskstats"
      "filesystem"
      "loadavg"
      "meminfo"
      "netdev"
      "os"
      "pressure"
      "stat"
      "textfile"
      "timex"
      "uname"
      "vmstat"
    ];
    extraFlags = [
      "--collector.disable-defaults"
      "--collector.textfile.directory=${textfileDir}"
      "--collector.filesystem.mount-points-exclude=${mountPointsExclude}"
      "--collector.filesystem.fs-types-exclude=${fsTypesExclude}"
    ];
  };

  ## Textfile metrics
  # Port of the role's failed-units-metric: the systemd collector is expensive
  # and "which units have failed" is all we want from it. The dpkg conffile
  # metric has no NixOS equivalent. On tmpfs, so a reboot starts over; the
  # first run after boot is at most five minutes away.
  systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

  systemd.services.failed-units-metric = {
    description = "Export failed systemd units for node_exporter";
    path = [
      config.systemd.package
      pkgs.gawk
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      out=${textfileDir}/failed_units.prom
      {
        echo '# HELP systemd_failed_unit Systemd unit in the failed state.'
        echo '# TYPE systemd_failed_unit gauge'
        count=0
        for unit in $(systemctl list-units --state=failed --plain --no-legend \
          | awk '{print $1}'); do
          echo "systemd_failed_unit{unit=\"$unit\"} 1"
          count=$((count + 1))
        done
        echo '# HELP systemd_failed_units_total Number of systemd units in the failed state.'
        echo '# TYPE systemd_failed_units_total gauge'
        echo "systemd_failed_units_total $count"
      } > "$out.$$"
      mv "$out.$$" "$out"
    '';
  };

  systemd.timers.failed-units-metric = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      RandomizedDelaySec = 30;
    };
  };

  ## Vector
  # The password reaches Vector as a systemd credential, read through its
  # directory secret backend; `vector validate` at build time does not resolve
  # secrets, so validation stays on.
  systemd.services.vector.serviceConfig.LoadCredential = [
    "monitoring-password:${config.age.secrets.monitoring-password.path}"
  ];

  services.vector = {
    enable = true;
    settings = {
      secret.credentials = {
        type = "directory";
        path = "/run/credentials/vector.service";
        remove_trailing_whitespace = true;
      };

      sources.node = {
        type = "prometheus_scrape";
        endpoints = [ "http://127.0.0.1:${toString nodePort}/metrics" ];
        # monitoring_scrape_interval of the Ansible agents.
        scrape_interval_secs = 30;
      };

      # vmagent adds job and instance itself; the dashboard and alert rules
      # select by instance.
      transforms.labels = {
        type = "remap";
        inputs = [ "node" ];
        source = ''
          .tags.job = "node"
          .tags.instance = "${host}"
        '';
      };

      sinks.victoriametrics = {
        type = "prometheus_remote_write";
        inputs = [ "labels" ];
        endpoint = "http://${vm.listenAddress}/api/v1/write";
        # Expects a 200; VictoriaMetrics answers 204 and every start would log
        # a failed healthcheck.
        healthcheck.enabled = false;
        auth = {
          strategy = "basic";
          user = vm.basicAuthUsername;
          password = "SECRET[credentials.monitoring-password]";
        };
      };
    };
  };
}
