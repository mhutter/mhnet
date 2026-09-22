# mhnet

Personal infrastructure: `rhea`, a Hetzner dedicated server running NixOS, and
a fleet of cheap VPS managed with Ansible. `just --list` shows the day-to-day
recipes for both.

## NixOS — rhea

`flake.nix`, `nixos/`, `modules/` and `services/` are `rhea`'s configuration;
the details are in `docs/`:

- [bootstrap](docs/bootstrap.md) — hardware and disk layout, installing from
  scratch, verifying the result, replacing a disk, editing secrets
- [backup](docs/backup.md) — restic to Backblaze B2: what is backed up, how
  modules contribute paths and pre-backup hooks, restoring
- [postgresql](docs/postgresql.md) — declaring per-app databases and roles,
  peer vs. password auth, rotating passwords
- [updates](docs/updates.md) — unattended upgrades and their schedule, failure
  and heartbeat alerting, garbage collection, recovering a bad one

Everything below documents the Ansible side.

## Monitoring

Push-based monitoring: every host (`monitoring_agent` role) runs
node_exporter bound to localhost, vmagent pushing its metrics to the hub via
Prometheus remote_write, and systemd-journal-upload streaming the journal to
VictoriaLogs. node_exporter runs an allowlist of collectors
(`monitoring_agent_enabled_collectors`) covering just the questions we care
about on a VPS — disk space, memory/OOM, CPU, reboots, clock sync, I/O and
traffic rates, versions — instead of the default everything. The hub (`monitoring_hub` role, host group `monitoring`) runs
VictoriaMetrics, VictoriaLogs and Grafana, with datasources and a lean
"mhnet node" dashboard provisioned (one row per question the collector
allowlist answers); the Grafana UI is exposed through the host's Cloudflare
tunnel. Alerting is Grafana's built-in one; the alert rules and a compact
Telegram notification template are provisioned from the repo
(`grafana-alerting.yml`), everything else — contact points, notification
policies, further rules — is configured in the UI. To use the template, set
the Telegram contact point's Message to
`{{ template "telegram.message" . }}` and its Parse mode to `HTML`.

The hub is the one deliberate exception to the no-inbound rule: its two
ingest ports (8428 metrics, 9428 logs) serve TLS (Let's Encrypt via
Cloudflare DNS-01, auto-renewed by certbot.timer) with basic auth, and are
reachable only from the fleet's addresses via `firewall_allow_tcp_from`.
vmagent authenticates natively; journal-upload sends the credential through
its `Header=` option.

Onboarding the hub (once):

1. Provision a VPS (~1 GB RAM), add it to the `monitoring` group in the
   vaulted inventory, and onboard it like any host (bootstrap, backup vars,
   cloudflared tunnel vars). The group also gets the `dns64` role: GitHub
   (VictoriaLogs downloads) and grafana.com (plugin installs) are IPv4-only.
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

Agents need no per-host vars. App roles feed their own metrics endpoints into
vmagent by dropping a scrape config into `/etc/vmagent/scrape.d/` (include
`monitoring_agent` with `tasks_from: scrape_config`); a single static target
can also come straight from the inventory via
`monitoring_agent_extra_scrape_configs`.

Operational notes:

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

## SilverBullet

The `silverbullet` role runs any number of [SilverBullet](https://silverbullet.md/)
spaces on one host: each entry in `silverbullet_instances` becomes a systemd
instance (`silverbullet@<name>`), a space folder
(`/var/lib/silverbullet/<name>`) and a public hostname on the host's tunnel,
all served by the same pinned binary. A space costs a few MB of RSS, so a
1 GB VPS hosts plenty of them.

```yaml
silverbullet_instances:
  - name: notes
    hostname: notes.example.com
    user: "me:<password>" # SilverBullet's single-user login
    title: Notes # optional, browser/app title
```

Instances listen on a unix socket (`/run/silverbullet/<name>/`) that
cloudflared connects to, so nothing binds a public port. Auth is
SilverBullet's own single-user login — it speaks no OIDC, so pocket-id is not
in the picture; use a distinct password per space.

Operational notes:

- SilverBullet is not packaged in Debian; the role installs a pinned static
  binary — bump `silverbullet_version` and re-run to update. Upstream's
  `silverbullet upgrade` self-updater would fight the versioned install, so
  it is not used. The host also gets the `dns64` role, because the download
  comes from IPv4-only GitHub.
- Backups need no pre-hook: a space is plain Markdown files, and
  `/var/lib/silverbullet` is registered as a backup path.
- Each instance exposes Prometheus counters on a localhost port (`3010` plus
  its position in the list, or the entry's `metrics_port`), scraped by vmagent
  through `/etc/vmagent/scrape.d/silverbullet.yml` and labelled `space=<name>`.
- Plugs can run shell commands as the service user; the role disables that
  (`silverbullet_shell_backend: "off"`).
- Dropping an instance from the inventory stops and disables its unit and
  removes its credentials, but keeps the space folder (delete it by hand once
  the backups are no longer wanted) and its tunnel ingress entry and DNS
  record (clean those up in the dashboard).

## Firefly III

The `firefly` role runs [Firefly III](https://www.firefly-iii.org/) (personal
finance manager) on `firefly_app_hostname`, served by nginx + php-fpm and
backed by PostgreSQL on the same host. Both hops are unix sockets
(`/run/firefly/nginx.sock`, `/run/firefly/php-fpm.sock`), so nothing binds a
TCP port and cloudflared is the only client.

Per-host inventory vars:

```yaml
firefly_app_hostname: fin.example.com
firefly_site_owner: me@example.com # address Firefly III mails from/to
firefly_app_key: "<32 chars: openssl rand -base64 24>"
```

`firefly_app_key` encrypts parts of the database, so keep an offsite copy of
it next to `backup_restic_password` — a restored dump is unreadable without
it. Auth is Firefly III's own login (it speaks no OIDC, so pocket-id is not in
the picture): register the first account, then close registration under
Administration > Settings and enable 2FA in the profile.

Sizing: the host has 2 GB, and the roles are tuned for it. Upstream states no
RAM requirement; the baseline here is ~250 MB (OS, cloudflared, the monitoring
agent, nginx), on top of which PostgreSQL takes `shared_buffers` (20% of RAM,
~390 MB) and php-fpm takes 192 MB of shared opcache plus its workers.
`pm = ondemand` means an idle host runs no PHP worker at all;
`firefly_fpm_max_children` (4) is enough for a browsing session alongside a
long-running import. Typical steady state is ~1.2 GB, leaving room for the
spikes a large CAMT/CSV import or an upgrade migration produces — those are
what `firefly_fpm_memory_limit` (512M, upstream's suggestion when a run dies
with "allowed memory size exhausted") is sized for. On a 1 GB host, drop
`firefly_fpm_max_children` to 2 and `firefly_opcache_memory_mb` to 128.

Operational notes:

- Firefly III is not packaged in Debian; the role installs a pinned release
  tarball (`firefly_version`, checksum-verified) from GitHub — the host also
  gets `dns64`, because GitHub is IPv4-only. The tarballs ship `vendor/` and
  the built frontend, so no composer or npm runs on the host.
- Releases are unpacked side by side under `/var/www/firefly-iii/releases/`
  and switched over by the `current` symlink after the migrations succeed;
  superseded releases are removed on the next run. To upgrade, bump
  `firefly_version` and re-run — the role runs `migrate --seed`,
  `firefly-iii:upgrade-database`, `firefly-iii:correct-database` and
  `firefly-iii:laravel-passport-keys`, and only then flips the symlink. Roll
  back by pointing `current` at the previous release (as long as it is still
  there) and restoring the database dump.
- PHP is pinned to `firefly_php_version` (8.5 on Ubuntu 26.04, the minimum
  Firefly III 6.6 accepts); bump it on a distro upgrade, since the pool
  config path is version-specific.
- State lives outside the releases: `/var/lib/firefly-iii/storage`
  (attachments, Passport keys) and `/etc/firefly-iii/.env`. Both are
  registered as backup paths, minus the regenerable caches and logs; the
  database itself comes from the PostgreSQL role's dump hook.
- A daily timer (`firefly-cron.timer`) runs `artisan firefly-iii:cron`, which
  is what makes recurring transactions, auto-budgets, subscription warnings
  and exchange rate updates happen.
- Locales: `firefly_language_packs` (`language-pack-de-base` by default) is
  installed and followed by a `locale-gen` run — the package registers its
  locales in `/var/lib/locales/supported.d/` but they have to be compiled
  before Firefly III can format amounts and dates with them. Add packs to the
  list for further languages; the interface language itself is
  `firefly_language` (`en_US`) with `firefly_locale` (`equal`, i.e. follow the
  language) deciding number and date formatting.
- Performance: opcache runs with `opcache.validate_timestamps=0`, so PHP never
  stats a file twice. This is safe because nginx resolves the `current`
  symlink before handing the path to php-fpm (a new release means new cache
  keys) and the role restarts php-fpm when it switches releases — but editing
  a file on the host by hand does nothing until
  `systemctl restart php8.5-fpm`. Static assets carry a `?v=<build time>` that
  changes with every release, so nginx sets a 30 day `expires` on them and
  gzips text assets for the tunnel hop.
- https scheme: cloudflared reaches nginx over a plain unix socket, so PHP
  would see the request as http and Firefly III would emit `http://` absolute
  URLs — including the API calls its own UI makes, which then fail with
  unhelpful messages like "Could not enable currency". `TRUSTED_PROXIES` does
  not help: 6.6.6 wires Laravel's default `TrustProxies` middleware without
  configuring it (`bootstrap/app.php`), so `X-Forwarded-Proto` is ignored and
  Firefly's own middleware class is never called. The nginx site therefore
  states the scheme itself (`fastcgi_param HTTPS on` plus `REQUEST_SCHEME` and
  `SERVER_PORT`), which is accurate: nothing but cloudflared can reach the
  socket, and it always terminates TLS. Re-check after a Firefly III upgrade
  in case upstream starts honouring the variable again.
- Where "please review the logs" points: the app logs to the journal, so
  `journalctl -u php8.5-fpm -f` (Laravel's syslog identifier is its
  snake-cased app name) while reproducing the action. nginx keeps its own
  `/var/log/nginx/error.log`, which is where FastCGI buffer and upstream
  errors show up instead. For a noisier trace, set `APP_LOG_LEVEL: debug` on
  the host and re-run the role.
- Logs go to the journal (`LOG_CHANNEL=syslog`) instead of piling up in
  `storage/logs`, so they end up in VictoriaLogs like everything else.

### Importing CAMT.053 / CSV files

Firefly III cannot import files itself; that is the separate
[data importer](https://docs.firefly-iii.org/how-to/data-importer/), which is
deliberately **not** deployed on the host — it has no login of its own, so
exposing it would put an unauthenticated write path in front of the API. Run
it locally when you need it instead:

```sh
docker run --rm -p 8080:8080 \
  -e FIREFLY_III_URL=https://fin.example.com \
  -e VANITY_URL=https://fin.example.com \
  -e FIREFLY_III_ACCESS_TOKEN=<personal access token> \
  -e IMPORT_DIR_ALLOWLIST=/import \
  -v "$PWD/statements:/import" \
  fireflyiii/data-importer:latest
# -> http://localhost:8080, upload the file, Ctrl-C when done
```

The access token comes from Firefly III's Options > Profile > OAuth > Personal
Access Tokens. The first UI run produces a JSON configuration file; later
imports of the same statement format can skip the UI:

```sh
docker run --rm -v "$PWD/statements:/import" \
  -e FIREFLY_III_URL=https://fin.example.com \
  -e FIREFLY_III_ACCESS_TOKEN=<personal access token> \
  -e IMPORT_DIR_ALLOWLIST=/import \
  fireflyiii/data-importer:latest \
  php artisan importer:import /import/config.json /import/statement.xml
```

## Backups

The `backup` role backs up every host to the `mhnet-restic` B2 bucket with
restic (daily backup + forget, weekly prune + check; retention 7 daily /
4 weekly / 12 monthly / 10 yearly). Roles contribute paths and pre-backup
hooks by dropping files into `/etc/backup/paths.d/` and `/etc/backup/pre.d/`.

Onboarding a new host:

1. `scripts/b2-create-restic-key.sh <hostname>` and paste the output into the
   host's vars in the vaulted inventory.
2. Add `backup_restic_password` (`openssl rand -base64 32`) next to it. Keep a
   copy outside this repo -- losing it means losing the backups.

The bucket's lifecycle must be set to "Keep only the last version" in the B2
console, otherwise pruned data lingers as hidden file versions.

Manual operations on a host: `backup-run snapshots`, `backup-run restore ...`
(wraps restic with the credentials from `/etc/backup/backup.env`).

## PostgreSQL

The `postgresql` role installs the server from apt and hooks it into the
backup role: a pre-backup hook dumps every database (custom format) plus the
globals to `/var/backups/postgresql`, which is registered as a backup path.
The dumps are the restore artifact; PGDATA is not backed up raw.

The role also renders `conf.d/10-tuning.conf` into the cluster's config
directory, with the memory settings derived from the host's RAM:
`shared_buffers` at 20% (below the usual 25%, because on these hosts the app
is the other large consumer), `effective_cache_size` at 50%,
`maintenance_work_mem` at 5% capped at 256 MB, plus `max_connections = 20`
and SSD-appropriate `random_page_cost`/`effective_io_concurrency`. Every
value is a `postgresql_*` variable that can be overridden per host, and
`postgresql_extra_settings` appends anything else. The packaged
`postgresql.conf` is left untouched (the role only checks that it reads
`conf.d`). Changing any of this restarts PostgreSQL, so the first run of this
on an existing host briefly takes its app's database down.

App roles include the role for the server and then create their database:

```yaml
- name: Install PostgreSQL
  ansible.builtin.include_role:
    name: postgresql

- name: Create my-app database
  ansible.builtin.include_role:
    name: postgresql
    tasks_from: database
  vars:
    postgresql_database_name: myapp
```

The owning role defaults to the database name (override with
`postgresql_database_owner`) and gets no password: app daemons run as a
matching system user and connect over the local socket, where Debian's
default `local all all peer` rule authenticates them.

## Cloudflare tunnels

Tunnel creation is a one-time dashboard step (create the tunnel, note its ID
and token). Everything else is the `cloudflared` role: the connector service
on the host, the per-hostname ingress configuration pushed to the Cloudflare
API — dashboard edits get overwritten — and the DNS CNAME `<app-host>` →
`<tunnel-id>.cfargotunnel.com`.

App roles include the role for the connector and then expose their hostname:

```yaml
- name: Install the Cloudflare tunnel connector
  ansible.builtin.include_role:
    name: cloudflared

- name: Expose my-app through the Cloudflare tunnel
  ansible.builtin.include_role:
    name: cloudflared
    tasks_from: expose
  vars:
    cloudflared_expose_hostname: my-app.example.com
    cloudflared_expose_service: "http://localhost:8080"
```

Hostnames are upserted into the tunnel's ingress, so several roles can share
one tunnel; removing a role leaves its ingress entry and DNS record behind
(clean up in the dashboard).

Required inventory vars: `cloudflare_account_id` and `cloudflare_api_token`
(API token with Account > Cloudflare Tunnel > Edit and Zone > DNS > Edit) at
the `all` level; `cloudflared_tunnel_id` and `cloudflared_tunnel_token` per
host.
