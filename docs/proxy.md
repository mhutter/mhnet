# Reverse proxy

Caddy, stock, configured in `modules/proxy.nix`: TLS for every HTTP service on
rhea, certificates obtained and renewed by Caddy itself, routing by hostname to
a loopback port or a Unix socket. Apps bind `127.0.0.1` or a socket;
`mhnet.proxy.hosts` is the only way onto the internet.

## Adding a host

```nix
mhnet.proxy.hosts."app.mhnet.app".upstream = "127.0.0.1:8080";
```

That is the whole change: certificate on first request, HTTP → HTTPS redirect,
access log. The one manual step is DNS — `A` `116.202.233.38`, `AAAA`
`2a01:4f8:241:4c27::1`, **DNS-only**: a Cloudflare orange cloud breaks
TLS-ALPN and makes `allowFrom` match the proxy instead of the client, so every
allowlist would accept everyone.

| Option        | Default | Meaning                                           |
| ------------- | ------- | ------------------------------------------------- |
| `upstream`    | —       | `host:port`, or `unix//run/app/http.sock`         |
| `aliases`     | `[ ]`   | extra hostnames on the same vhost and certificate |
| `allowFrom`   | `[ ]`   | client IPs/CIDRs allowed in; empty means public   |
| `forwardAuth` | `null`  | delegate authentication to an external service    |
| `log`         | `true`  | write `/var/log/caddy/access-<host>.log`          |
| `extraConfig` | `""`    | extra Caddyfile directives for this vhost         |

Removing a host revokes nothing; its certificate stays in the data directory
until it expires.

## Restricting a host

```nix
mhnet.proxy.hosts."private.mhnet.app" = {
  upstream = "127.0.0.1:8081";
  allowFrom = [ "203.0.113.0/24" "2001:db8:1234::/48" ];
};
```

Everything else gets a bare 403. The ACME HTTP-01 challenge is answered before
site routing, so renewals still work. Test with both `curl -4` and `curl -6` — a
v4 allowlist without its v6 counterpart looks fine from one side only.

## Authentication

`forwardAuth` emits `forward_auth` plus a passthrough for the sign-in flow,
shaped for oauth2-proxy:

```nix
mhnet.proxy.hosts."app.mhnet.app" = {
  upstream = "127.0.0.1:8080";
  forwardAuth.upstream = "127.0.0.1:4180";
};
```

**Nothing runs an auth service yet** — this is the hook only. The service must
answer `uri` (default `/oauth2/auth`) and own `prefix` (default `/oauth2`).

## Certificates

Caddy's own ACME client, HTTP-01 / TLS-ALPN against Let's Encrypt. Account key
and certificates live in `/nix/persist/var/lib/caddy` (`dataDir`), and so are
backed up. Keep it there: at the tmpfs default, every reboot would re-issue
until Let's Encrypt's duplicate-certificate limit hits.

The ACME contact address comes from `secrets/caddy-env.age` as `ACME_EMAIL=…`,
expanded at start. A missing value passes `just dry` and fails the unit on
start.

For a host whose DNS or reachability is uncertain, deploy once against staging:

```nix
services.caddy.acmeCA = "https://acme-staging-v02.api.letsencrypt.org/directory";
```

## No plugins

`pkgs.caddy.withPlugins` is an xcaddy build behind a hash maintained by hand on
every Caddy bump — it would break the unattended lock bump (`docs/updates.md`).
Hence authentication through `forward_auth`, not `caddy-security`, and no
DNS-01: every hostname must be public and reachable on port 80, no wildcards.
Should DNS-01 become necessary: `security.acme` with lego's Cloudflare support
and `useACMEHost`, no Caddy plugin needed.

## Observability

- Access logs: `/var/log/caddy/access-<host>.log`, JSON, rolled by Caddy (100
  MiB × 10), shipped to VictoriaLogs as `log:caddy-access`
  (`docs/monitoring.md`).
- Caddy's own log: `journalctl -u caddy`.
- Metrics on the admin endpoint `localhost:2019/metrics`, scraped as
  `job="caddy"`.
- A failure of `caddy.service` pushes to ntfy.
