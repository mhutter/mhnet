## Monitoring agent: host and service metrics, the journal and Caddy's access
## logs, shipped by Vector to VictoriaMetrics and VictoriaLogs
#
# The NixOS counterpart of ansible/roles/monitoring_agent. The hub runs on this
# host (services/monitoring.nix), so Vector writes to it on loopback: no TLS,
# and no disk buffer for hub outages.
{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  host = config.networking.hostName;
  nodePort = config.services.prometheus.exporters.node.port;
  vm = config.services.victoriametrics;
  textfileDir = "/var/lib/prometheus-node-exporter";
  vl = config.services.victorialogs;

  # Scrape targets by job name; see the Metrics section of Vector below.
  scrapeTargets = {
    node = "http://127.0.0.1:${toString nodePort}/metrics";
    # Admin endpoint; `metrics` in modules/proxy.nix adds per-host HTTP metrics.
    caddy = "http://127.0.0.1:2019/metrics";
    grafana = "http://${grafana.http_addr}:${toString grafana.http_port}/metrics";
    immich-api = "http://127.0.0.1:${config.services.immich.environment.IMMICH_API_METRICS_PORT}/metrics";
    immich-microservices = "http://127.0.0.1:${config.services.immich.environment.IMMICH_MICROSERVICES_METRICS_PORT}/metrics";
  };
  hubTargets = {
    victoriametrics = "http://${vm.listenAddress}/metrics";
    victorialogs = "http://${vl.listenAddress}/metrics";
  };
  grafana = config.services.grafana.settings.server;
  vectorDataDir = "${persist}/var/lib/vector";

  # Both hub daemons check the same credential.
  hubAuth = daemon: {
    strategy = "basic";
    user = daemon.basicAuthUsername;
    password = "SECRET[credentials.monitoring-password]";
  };

  # Acknowledgements: a source only moves its checkpoint once VictoriaLogs
  # took the batch, so a restart re-sends rather than loses. The healthcheck
  # would probe the insert URL itself.
  logSink =
    { inputs, streamFields }:
    {
      type = "http";
      inherit inputs;
      uri = "http://${vl.listenAddress}/insert/jsonline?_stream_fields=${lib.concatStringsSep "," streamFields}";
      encoding.codec = "json";
      framing.method = "newline_delimited";
      auth = hubAuth vl;
      acknowledgements.enabled = true;
      healthcheck.enabled = false;
    };

  journalFields = [
    "PRIORITY"
    "SYSLOG_IDENTIFIER"
    "MESSAGE_ID"
    "UNIT"
    "USER_UNIT"
    "_BOOT_ID"
    "_MACHINE_ID"
    "_SYSTEMD_UNIT"
    "_SYSTEMD_USER_UNIT"
    "_SYSTEMD_INVOCATION_ID"
    "_TRANSPORT"
    "_PID"
    "_UID"
    "_COMM"
  ];

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
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
    "d ${vectorDataDir} 0700 vector vector -" # checkpoints, see Vector below
  ];

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

  ## Journal
  # Logs live in VictoriaLogs for 90 days (services/monitoring.nix); locally the
  # journal only needs to cover recent history, early boot and VictoriaLogs
  # being down. The size cap is a safety net for a runaway unit.
  services.journald.extraConfig = ''
    MaxRetentionSec=14d
    SystemMaxUse=1G
  '';

  ## Vector
  # A static user instead of the module's DynamicUser: the read positions in
  # the journal and the Caddy logs have to survive a reboot, or every boot
  # would ship everything again. The groups grant read access to both.
  users.users.vector = {
    isSystemUser = true;
    group = "vector";
    extraGroups = [
      "systemd-journal"
      config.services.caddy.group
    ];
  };
  users.groups.vector = { };

  # The password reaches Vector as a systemd credential, read through its
  # directory secret backend; `vector validate` at build time does not resolve
  # secrets, so validation stays on.
  systemd.services.vector = {
    unitConfig.RequiresMountsFor = vectorDataDir;
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "vector";
      Group = "vector";
      StateDirectory = lib.mkForce "";
      ReadWritePaths = [ vectorDataDir ];
      # DynamicUser implied it.
      ProtectSystem = "strict";
      LoadCredential = [
        "monitoring-password:${config.age.secrets.monitoring-password.path}"
      ];
    };
  };

  services.vector = {
    enable = true;
    settings = {
      data_dir = vectorDataDir;

      secret.credentials = {
        type = "directory";
        path = "/run/credentials/vector.service";
        remove_trailing_whitespace = true;
      };

      ## Metrics
      # monitoring_scrape_interval of the Ansible agents.
      sources.scrape = {
        type = "prometheus_scrape";
        endpoints = lib.attrValues scrapeTargets;
        endpoint_tag = "endpoint";
        scrape_interval_secs = 30;
      };

      # The hub daemons guard /metrics with the ingest credential.
      sources.scrape_hub = {
        type = "prometheus_scrape";
        endpoints = lib.attrValues hubTargets;
        endpoint_tag = "endpoint";
        scrape_interval_secs = 30;
        auth = hubAuth vm;
      };

      # Errors, dropped events and throughput of Vector itself.
      sources.vector = {
        type = "internal_metrics";
        scrape_interval_secs = 30;
      };

      # Counters and gauges answer "is shipping healthy" (errors, discarded and
      # sent events); the latency and buffer histograms are ~90% of the series.
      # Labelled here rather than below: their `endpoint` tags are sink and
      # scrape URLs, which the job lookup would misread.
      transforms.vector_metrics = {
        type = "remap";
        inputs = [ "vector" ];
        source = ''
          if .type != "counter" && .type != "gauge" { abort }
          .tags.job = "vector"
          .tags.instance = "${host}"
        '';
      };

      # Of Grafana's ~6000 series only alerting matters here: failed rule
      # evaluations and notifications. The rest are its internals.
      transforms.grafana = {
        type = "filter";
        inputs = [ "scrape" ];
        condition = ''
          .tags.endpoint != "${scrapeTargets.grafana}" ||
            starts_with(string!(.name), "grafana_alerting_") || .name == "grafana_build_info"
        '';
      };

      # vmagent adds job and instance itself; the dashboard and alert rules
      # select by instance.
      transforms.labels = {
        type = "remap";
        inputs = [
          "grafana"
          "scrape_hub"
        ];
        source = ''
          jobs = ${builtins.toJSON (lib.mapAttrs' (job: url: lib.nameValuePair url job) (scrapeTargets // hubTargets))}
          .tags.job = get!(jobs, [.tags.endpoint])
          del(.tags.endpoint)
          .tags.instance = "${host}"
        '';
      };

      sinks.victoriametrics = {
        type = "prometheus_remote_write";
        inputs = [
          "labels"
          "vector_metrics"
        ];
        endpoint = "http://${vm.listenAddress}/api/v1/write";
        # Expects a 200; VictoriaMetrics answers 204 and every start would log
        # a failed healthcheck.
        healthcheck.enabled = false;
        auth = hubAuth vm;
      };

      ## Logs
      # Without a checkpoint (first start, or a lost data_dir) both sources
      # start at the end: a gap instead of shipping days of logs twice. With
      # one, they resume from it, across boots.
      sources.journal = {
        type = "journald";
        current_boot_only = false;
        since_now = true;
        # Its own errors about shipping must not loop back into the pipeline.
        exclude_matches._SYSTEMD_UNIT = [ "vector.service" ];
      };

      sources.caddy = {
        type = "file";
        # Caddy's rolled files match too; the fingerprint of their first line
        # recognises them as already read.
        include = [ "${config.services.caddy.logDir}/access-*.log" ];
        read_from = "end";
      };

      # Shaped like what VictoriaLogs' /insert/journald makes of
      # systemd-journal-upload, as on the Ansible fleet: journald field names,
      # its level names, the same stream fields. Only the fields worth
      # querying are kept; _CMDLINE, _EXE, capabilities and the like are not.
      transforms.journal_fields = {
        type = "remap";
        inputs = [ "journal" ];
        source = ''
          levels = ["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"]
          fields = ${builtins.toJSON journalFields}
          out = filter(.) -> |key, _value| { includes(fields, key) }
          out._time = .timestamp
          out._msg = .message
          out._HOSTNAME = .host
          if is_string(.PRIORITY) {
            out.level = get(levels, [to_int(.PRIORITY) ?? 6]) ?? null
          }
          . = out
        '';
      };

      # One line per request, readable in a log list; the rest stays
      # structured. Response headers and TLS details are dropped, as are
      # request headers but the user agent and referer.
      transforms.caddy_fields = {
        type = "remap";
        inputs = [ "caddy" ];
        source = ''
          r = parse_json!(.message)
          req = object!(r.request)
          . = {
            "_time": from_unix_timestamp!(to_int(to_float!(r.ts) * 1000000), unit: "microseconds"),
            "_msg": join!([string!(req.method), string!(req.host) + string!(req.uri), to_string!(r.status)], " "),
            "_HOSTNAME": "${host}",
            "log": "caddy-access",
            # Some clients send the port along, which would split the stream.
            "vhost": replace(string!(req.host), r':\d+$', ""),
            "level": r.level,
            "status": r.status,
            "duration": r.duration,
            "size": r.size,
            "bytes_read": r.bytes_read,
            "user_id": r.user_id,
            "remote_ip": req.remote_ip,
            "client_ip": req.client_ip,
            "proto": req.proto,
            "method": req.method,
            "uri": req.uri,
            "user_agent": req.headers."User-Agent"[0],
            "referer": req.headers.Referer[0],
          }
          . = compact(.)
        '';
      };

      sinks.victorialogs_journal = logSink {
        inputs = [ "journal_fields" ];
        streamFields = [
          "_HOSTNAME"
          "_MACHINE_ID"
          "_SYSTEMD_UNIT"
        ];
      };

      sinks.victorialogs_caddy = logSink {
        inputs = [ "caddy_fields" ];
        streamFields = [
          "_HOSTNAME"
          "log"
          "vhost"
        ];
      };
    };
  };
}
