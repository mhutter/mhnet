# Monitoring

Push-based: every host ships its metrics and journal to the hub on rhea
(`services/monitoring.nix`) — VictoriaMetrics, VictoriaLogs and Grafana, on
loopback behind Caddy. No host needs an inbound port for it.

| Hostname            | Serves                               |
| ------------------- | ------------------------------------ |
| `metrics.mhnet.app` | VictoriaMetrics, basic auth (ingest) |
| `logs.mhnet.app`    | VictoriaLogs, basic auth (ingest)    |
| `grafana.mhnet.app` | Grafana UI                           |

All three need DNS-only A/AAAA records (`docs/proxy.md`). Retention: metrics 12
months, logs 90 days.

## Secrets

- `monitoring-password.age` — the ingest password; must match the vault's
  `monitoring_remote_write_password`, which the fleet sends.
- `grafana-secret-key.age` — the key `grafana.db` is encrypted with (Grafana's
  old built-in default, inherited from the retired Ansible hub). A different key
  breaks every stored secret: datasource passwords, the Telegram bot token.

## Fleet agents

The `monitoring_agent` role, on every host in `site.yml`:

- **node_exporter** on localhost, with an allowlist of collectors
  (`monitoring_agent_enabled_collectors`) — disk space, memory/OOM, CPU,
  reboots, clock sync, I/O and traffic rates, versions — instead of the default
  everything.
- **vmagent** scrapes it and pushes via remote_write, buffering up to 512 MiB on
  disk while the hub is unreachable.
- **systemd-journal-upload** streams the journal to VictoriaLogs, resuming from
  its cursor after outages. Needs systemd ≥ 258 for its `Header=` auth.

Vars, at the `all` level of the vaulted inventory: `monitoring_metrics_url`,
`monitoring_logs_url` (`https://metrics.mhnet.app`, `https://logs.mhnet.app`)
and `monitoring_remote_write_password`. None per host.

App roles add scrape targets with a drop-in (`include_role` of
`monitoring_agent`, `tasks_from: scrape_config`); a single static target can
come from the inventory via `monitoring_agent_extra_scrape_configs`.

Two textfile metrics replace expensive or missing collectors:

- `systemd_failed_units_total` and `systemd_failed_unit{unit="..."}`, every
  five minutes — node_exporter's systemd collector cost more than all others
  combined.
- `dpkg_conffile_leftovers`, daily: `*.dpkg-dist` and friends under `/etc`.
  dpkg never prompts (`force-confold`, `roles/common`) and keeps the
  maintainer's version beside the file; diff and delete it once reconciled.

## rhea's own metrics and logs

`services/monitoring-agent.nix` is the NixOS counterpart, with Vector in place
of vmagent and journal-upload, writing to the hub on loopback.

- **Metrics**: node_exporter with the same allowlist, `job="node"`,
  `instance="rhea"`. The failed-units textfile metric is ported; the dpkg one
  has no equivalent, so its panel stays empty for rhea.
- **Service metrics**, one `job` each: `caddy`, `victoriametrics`,
  `victorialogs`, `immich-api` and `immich-microservices` (job queues only),
  `grafana` (`grafana_alerting_*` only), `vector` (no histograms). PostgreSQL,
  MySQL and Redis would need an exporter each.
- **Journal**: shaped like the fleet's entries (journald field names, `level`,
  streams by `_HOSTNAME`, `_MACHINE_ID`, `_SYSTEMD_UNIT`), a subset of the
  fields. Locally kept 14 days, 1 GB at most.
- **Caddy access logs**: `log:caddy-access`, one stream per `vhost`; e.g.
  `log:caddy-access vhost:immich.mhnet.app status:>=500`.

Vector checkpoints under `/nix/persist/var/lib/vector` and advances only once
VictoriaLogs accepted a batch: restarts resume without loss, possibly sending a
few entries twice. Without a checkpoint it starts at the end — losing the
directory means a gap, not a second copy.

## Grafana and alerting

Datasources, the "mhnet node" dashboard (`services/monitoring/dashboards/`) and
the alert rules (`services/monitoring/grafana-alerting.yml`) are provisioned on
every start. Users, contact points and notification policies live in
`grafana.db` and are managed in the UI.

- `FailedUnits` — one alert per failed unit; the notification links its
  journal.
- `ConffileLeftovers` — `dpkg_conffile_leftovers > 0`.
- `StaleTextfileMetrics` — a textfile older than 25h, i.e. a broken timer.

The provisioned Telegram template needs the contact point's Message set to
`{{ template "telegram.message" . }}` and Parse mode to `HTML`.

## Backups

VictoriaMetrics is snapshotted and Grafana's db dumped with `VACUUM INTO`
before each run; the live data of both is excluded. To restore VictoriaMetrics,
copy the snapshot's contents into an empty data directory. VictoriaLogs is not
backed up.
