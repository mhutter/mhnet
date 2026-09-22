# Monitoring

Push-based monitoring: every host (`monitoring_agent` role) runs node_exporter
bound to localhost, vmagent pushing its metrics to the hub via Prometheus
remote_write, and systemd-journal-upload streaming the journal to VictoriaLogs.
node_exporter runs an allowlist of collectors
(`monitoring_agent_enabled_collectors`) covering just the questions we care
about on a VPS — disk space, memory/OOM, CPU, reboots, clock sync, I/O and
traffic rates, versions — instead of the default everything.

The hub (`monitoring_hub` role, host group `monitoring`) runs VictoriaMetrics,
VictoriaLogs and Grafana, with datasources and a lean "mhnet node" dashboard
provisioned (one row per question the collector allowlist answers); the Grafana
UI is exposed through the host's Cloudflare tunnel. Alerting is Grafana's
built-in one; the alert rules and a compact Telegram notification template are
provisioned from the repo (`grafana-alerting.yml`), everything else — contact
points, notification policies, further rules — is configured in the UI. To use
the template, set the Telegram contact point's Message to
`{{ template "telegram.message" . }}` and its Parse mode to `HTML`.

The hub is the one deliberate exception to the no-inbound rule: its two ingest
ports (8428 metrics, 9428 logs) serve TLS (Let's Encrypt via Cloudflare DNS-01,
auto-renewed by certbot.timer) with basic auth, and are reachable only from the
fleet's addresses via `firewall_allow_tcp_from`. vmagent authenticates natively;
journal-upload sends the credential through its `Header=` option.

## Onboarding the hub (once)

1. Provision a VPS (~1 GB RAM), add it to the `monitoring` group in the vaulted
   inventory, and onboard it like any host (bootstrap, backup vars, cloudflared
   tunnel vars). The group also gets the `dns64` role: GitHub (VictoriaLogs
   downloads) and grafana.com (plugin installs) are IPv4-only.
2. Vars at the `all` level: `monitoring_ingest_hostname` (e.g.
   `mon.example.com`) and `monitoring_remote_write_password`
   (`openssl rand -base64 32`).
3. Vars on the hub: `monitoring_grafana_hostname`, `grafana_admin_password`,
   and the ingest firewall openings — sources must be literal IPv6 addresses
   (use an explicit list if `ansible_host` values are DNS names):

   ```yaml
   firewall_allow_tcp_from:
     - ports: [8428, 9428]
       sources: "{{ groups['all'] | map('extract', hostvars, 'ansible_host') | list }}"
   ```

## Agents

Agents need no per-host vars. App roles feed their own metrics endpoints into
vmagent by dropping a scrape config into `/etc/vmagent/scrape.d/` (include
`monitoring_agent` with `tasks_from: scrape_config`); a single static target can
also come straight from the inventory via
`monitoring_agent_extra_scrape_configs`.

## Operational notes

- The roles need `victoria-metrics` ≥ 1.112 (Ubuntu 26.04 universe ships
  1.112) for `-httpAuth.password=file:///...`, and systemd ≥ 258 (26.04
  ships 259) for journal-upload's `Header=` auth.
- VictoriaLogs is not packaged in Debian; the role installs a pinned static
  binary — bump `monitoring_hub_victorialogs_version` and re-run to update.
- Grafana datasource plugins: since Grafana 13.2 the core datasources are no
  longer in the deb but downloaded from grafana.com on startup, so
  `/var/lib/grafana/plugins` must stay writable by the `grafana` user (a
  root-owned one breaks every query with "plugin not registered"). The role
  preinstalls only `prometheus` (which backs the VictoriaMetrics datasource)
  and `victoriametrics-logs-datasource` via `[plugins] preinstall`, and
  disables the rest of Grafana's default preinstall list through
  `disable_plugins` — see `monitoring_hub_grafana_plugins` /
  `monitoring_hub_grafana_disabled_plugins`. Grafana keeps them updated
  itself; if a new Grafana release adds unwanted plugins to its defaults,
  add them to the disabled list.
- Backups: a pre-hook snapshots VictoriaMetrics (restore: restic-restore the
  snapshot and copy its contents into an empty `/var/lib/victoria-metrics`)
  and dumps Grafana's SQLite db. VictoriaLogs data is deliberately not
  backed up.
- Retention defaults: metrics 12 months, logs 90 days
  (`monitoring_hub_metrics_retention` / `monitoring_hub_logs_retention`).
- Config drift: dpkg never prompts for conffile changes (`force-confold`,
  roles/common) and keeps the maintainer's version as `*.dpkg-dist`. A daily
  timer on every agent exports `dpkg_conffile_leftovers` (count of
  `*.dpkg-dist`/`*.dpkg-new`/`*.dpkg-old`/`*.ucf-dist` under `/etc`) via the
  node_exporter textfile collector; alert on `> 0` in Grafana, then diff the
  leftover against the kept file and delete it once reconciled.
- Failed units: node_exporter's systemd collector is disabled (it cost more
  than all other collectors combined); instead a five-minute timer exports
  `systemd_failed_units_total` plus one `systemd_failed_unit{unit="..."}`
  series per failed unit. The provisioned `FailedUnits` alert fires per
  failed unit, naming it in the message; the Telegram notification links
  the unit's journal in VictoriaLogs.
- Textfile metrics go stale silently if their timer breaks; the provisioned
  `StaleTextfileMetrics` alert fires when any textfile is older than 25h,
  covering both of the above (the dpkg timer is the slowest at daily).
