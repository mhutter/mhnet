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

## Cloudflare tunnels

Tunnel creation is a one-time dashboard step (create the tunnel, note its ID
and token). Everything else is Ansible: the connector service on the host, the
ingress configuration (backend URL derived from the role's app URL/port vars)
pushed to the Cloudflare API on each run — dashboard edits get overwritten —
and the DNS CNAME `<app-host>` → `<tunnel-id>.cfargotunnel.com`.

Required inventory vars: `cloudflare_account_id` and `cloudflare_api_token`
(API token with Account > Cloudflare Tunnel > Edit and Zone > DNS > Edit) at
the `all` level; `pocket_id_tunnel_id` and `pocket_id_tunnel_token` per host.
