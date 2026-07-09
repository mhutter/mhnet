# mhnet Ansible

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
