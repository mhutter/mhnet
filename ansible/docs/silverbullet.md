# SilverBullet

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

## Operational notes

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
