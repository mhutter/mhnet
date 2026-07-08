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

## Backlog

- [x] pocket-id: expose
- [x] pocket-id backup
- [ ] apt-dater config file
- [ ] encrypted inventory
