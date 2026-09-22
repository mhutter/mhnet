# Firefly III

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

## Sizing

The host has 2 GB, and the roles are tuned for it. Upstream states no RAM
requirement; the baseline here is ~250 MB (OS, cloudflared, the monitoring
agent, nginx), on top of which PostgreSQL takes `shared_buffers` (20% of RAM,
~390 MB) and php-fpm takes 192 MB of shared opcache plus its workers.
`pm = ondemand` means an idle host runs no PHP worker at all;
`firefly_fpm_max_children` (4) is enough for a browsing session alongside a
long-running import. Typical steady state is ~1.2 GB, leaving room for the
spikes a large CAMT/CSV import or an upgrade migration produces — those are
what `firefly_fpm_memory_limit` (512M, upstream's suggestion when a run dies
with "allowed memory size exhausted") is sized for. On a 1 GB host, drop
`firefly_fpm_max_children` to 2 and `firefly_opcache_memory_mb` to 128.

## Operational notes

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

## Importing CAMT.053 / CSV files

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
