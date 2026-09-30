# Firefly III

The `firefly` role runs [Firefly III](https://www.firefly-iii.org/) (personal
finance) on `firefly_app_hostname`: nginx + php-fpm, PostgreSQL on the same
host. Both hops are unix sockets, so nothing binds a TCP port and cloudflared is
the only client.

Per-host vars: `firefly_app_hostname`, `firefly_site_owner`, and
`firefly_app_key` (32 characters, `openssl rand -base64 24`). The key encrypts
parts of the database — keep an offsite copy next to `backup_restic_password`,
or a restored dump is unreadable.

Auth is Firefly III's own login (no OIDC): register the first account, then
close registration under Administration > Settings and enable 2FA. No SMTP:
mails are written to the log only.

## Sizing

Tuned for 2 GB: ~250 MB baseline (OS, cloudflared, monitoring agent, nginx),
PostgreSQL `shared_buffers` ~390 MB, php-fpm 192 MB opcache plus workers.
`pm = ondemand` runs no PHP worker when idle; `firefly_fpm_max_children` (4)
covers browsing alongside an import. Steady state ~1.2 GB, leaving room for
import and migration spikes, which `firefly_fpm_memory_limit` (512M) is sized
for. On 1 GB: `firefly_fpm_max_children: 2`, `firefly_opcache_memory_mb: 128`.

## Upgrades

Not packaged in Debian: the role installs the pinned, checksum-verified release
tarball (`firefly_version`) from GitHub — hence `dns64` on the host. Releases
unpack side by side under `/var/www/firefly-iii/releases/`; the `current`
symlink flips only after the migrations succeed, and superseded releases go on
the next run. To upgrade, bump `firefly_version` and re-run. To roll back, point
`current` at the previous release and restore the database dump.

PHP is pinned to `firefly_php_version` (8.5); bump it on a distro upgrade, the
pool config path is version-specific.

## Operational notes

- State: `/var/lib/firefly-iii/storage` and `/etc/firefly-iii/.env`, both
  backed up minus caches and logs; the database comes from the PostgreSQL dump.
- `firefly-cron.timer` runs `artisan firefly-iii:cron` daily: recurring
  transactions, auto-budgets, subscription warnings, exchange rates.
- Language `firefly_language` (`de_CH`), formatting `firefly_locale` (`equal`:
  follow the language). Further languages need their pack in
  `firefly_language_packs`; the role runs `locale-gen` after installing.
- opcache runs with `validate_timestamps=0`. Safe because nginx resolves the
  `current` symlink (a new release means new cache keys) and the role restarts
  php-fpm on a switch — but a hand edit on the host does nothing until
  `systemctl restart php8.5-fpm`.
- **https scheme.** PHP sees plain http from the socket and Firefly would emit
  `http://` URLs, breaking its own UI's API calls ("Could not enable
  currency"). 6.6.6 ignores `TRUSTED_PROXIES`, so the nginx site asserts
  `HTTPS on` itself — accurate, since only cloudflared reaches the socket.
  Re-check after upgrades.
- Logs go to the journal: `journalctl -u php8.5-fpm -f` while reproducing.
  FastCGI and upstream errors land in `/var/log/nginx/error.log`. For more
  detail, set `APP_LOG_LEVEL=debug` in `/etc/firefly-iii/.env` and restart
  php-fpm; the next role run reverts it.

## Importing CAMT.053 / CSV

The [data importer](https://docs.firefly-iii.org/how-to/data-importer/) is
deliberately not deployed: it has no login of its own. Run it locally, with a
personal access token from Options > Profile > OAuth:

```sh
docker run --rm -p 8080:8080 \
  -e FIREFLY_III_URL=https://fin.example.com \
  -e VANITY_URL=https://fin.example.com \
  -e FIREFLY_III_ACCESS_TOKEN=<token> \
  -e IMPORT_DIR_ALLOWLIST=/import \
  -v "$PWD/statements:/import" \
  fireflyiii/data-importer:latest
```

The first UI run produces a JSON config; later imports of the same format skip
the UI:

```sh
docker run --rm -v "$PWD/statements:/import" \
  -e FIREFLY_III_URL=https://fin.example.com \
  -e FIREFLY_III_ACCESS_TOKEN=<token> \
  -e IMPORT_DIR_ALLOWLIST=/import \
  fireflyiii/data-importer:latest \
  php artisan importer:import /import/config.json /import/statement.xml
```
