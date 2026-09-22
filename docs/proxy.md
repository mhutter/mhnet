# Reverse proxy

Caddy, configured in `modules/proxy.nix`. It terminates TLS for every HTTP
service on `rhea`, obtains and renews the certificates itself, and routes by
hostname to a loopback port or a Unix socket.

Nothing listens publicly except Caddy: apps bind `127.0.0.1` or a socket, and
`mhnet.proxy.hosts` is the only thing that puts them on the internet.

## Adding a host

Next to the rest of the app's config:

```nix
mhnet.proxy.hosts."app.mhnet.app".upstream = "127.0.0.1:8080";
```

That is the whole change: Caddy opens 80 and 443, obtains a certificate for
`app.mhnet.app` on first request, redirects HTTP to HTTPS, and writes an access
log. The DNS record is the one manual step — an `A` to `116.202.233.38` and an
`AAAA` to `2a01:4f8:241:4c27::1`, **DNS-only** (see [Gotchas](#gotchas)).

The full set of per-host options:

| Option        | Default | Meaning                                                    |
| ------------- | ------- | ---------------------------------------------------------- |
| `upstream`    | —       | `host:port`, or `unix//run/app/http.sock`                  |
| `aliases`     | `[ ]`   | extra hostnames on the same vhost and certificate          |
| `allowFrom`   | `[ ]`   | client IPs/CIDRs allowed in; empty means public            |
| `forwardAuth` | `null`  | delegate authentication to an external service (see below) |
| `log`         | `true`  | write `/var/log/caddy/access-<host>.log`                   |
| `extraConfig` | `""`    | extra Caddyfile directives for this vhost                  |

## Restricting a host to known addresses

```nix
mhnet.proxy.hosts."private.mhnet.app" = {
  upstream = "127.0.0.1:8081";
  allowFrom = [
    "203.0.113.0/24"
    "2001:db8:1234::/48"
  ];
};
```

Everything outside the list gets a bare 403. The certificate is still issued
normally: the ACME HTTP-01 challenge is answered by Caddy before site routing,
so the allowlist does not lock out renewals.

Test both stacks — `curl -4` and `curl -6` — because a v4 allowlist that forgot
its v6 counterpart looks fine from one and locks you out from the other.

## Authentication

`forwardAuth` emits Caddy's `forward_auth` plus a passthrough for the sign-in
flow, aimed at `oauth2-proxy`:

```nix
mhnet.proxy.hosts."app.mhnet.app" = {
  upstream = "127.0.0.1:8080";
  forwardAuth.upstream = "127.0.0.1:4180";
};
```

**Nothing runs an auth service yet** — this is the hook, not a working setup.
Whatever answers on `forwardAuth.upstream` has to accept `uri` (default
`/oauth2/auth`) and own the `prefix` (default `/oauth2`).

## Certificates

Caddy's own ACME client, HTTP-01 / TLS-ALPN against Let's Encrypt. No DNS
credentials and no `security.acme`.

The account key and the certificates live in `/nix/persist/var/lib/caddy`
(`services.caddy.dataDir`), which puts them in the backup automatically. That
directory is load-bearing: `/` is tmpfs, so if it were left at the default
`/var/lib/caddy` every reboot would look like a fresh install and Caddy would
re-issue until Let's Encrypt's five-duplicates-per-week limit stopped it.

The ACME contact address is **not** in this repository. It comes from
`secrets/caddy-env.age` as `ACME_EMAIL=…`, which Caddy expands from
`{$ACME_EMAIL}` at parse time; `/etc/caddy/caddy_config` only ever holds the
placeholder. To change it: `agenix -e secrets/caddy-env.age`, then `just switch`.

When adding a host whose DNS or firewall is uncertain, point Caddy at the
staging CA for one deploy so a mistake burns staging quota instead of the real
rate limit:

```nix
services.caddy.acmeCA = "https://acme-staging-v02.api.letsencrypt.org/directory";
```

## No plugins

`pkgs.caddy.withPlugins` rebuilds Caddy with `xcaddy` behind a fixed-output
hash that has to be updated by hand on every Caddy version bump. That would
break the weekly `flake.lock` bump and the unattended upgrade that follows it
(`docs/updates.md`), so this setup stays on stock Caddy. The consequences are
deliberate:

- authentication goes through `forward_auth` to a separate service, not through
  `caddy-security`
- there is no DNS-01, so every hostname must be publicly resolvable and
  reachable on port 80, and wildcards are out

If DNS-01 ever becomes necessary, the way in is `security.acme` with lego's
built-in Cloudflare support plus `virtualHosts.<n>.useACMEHost` — no plugin
needed on the Caddy side.

## Observability

- Access logs: `/var/log/caddy/access-<host>.log`, JSON, rolled by Caddy itself
  at 100 MiB keeping 10 files. `/var/log` is persisted but excluded from
  backups.
- Caddy's own log: `journalctl -u caddy`, level `ERROR` by default.
- Metrics: Prometheus format on the admin endpoint, `localhost:2019/metrics`.
  Nothing scrapes them yet.
- Failures push to ntfy — `caddy.service` is in `mhnet.notify.units`.

## Gotchas

- **DNS-only records.** A Cloudflare orange cloud (or any proxy in front)
  breaks TLS-ALPN and, worse, makes `allowFrom` match the proxy instead of the
  client — every allowlist would then accept everyone. Fixing that would mean
  `trusted_proxies` in the global config and the `client_ip` matcher in place of
  `remote_ip`.
- **The secret is read at start, not at build.** A missing or empty
  `ACME_EMAIL` passes `just dry` and then fails the Caddyfile parse when the
  unit starts.
- **Removing a host does not revoke anything.** The vhost disappears; the
  certificate stays in `dataDir` until it expires.
