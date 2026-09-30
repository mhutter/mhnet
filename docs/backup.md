# Backups

restic to Backblaze B2, one repository per host under
`s3:<endpoint>/mhnet-restic/<hostname>`. On rhea it is `modules/backup.nix`, on
the fleet the `backup` role; both follow the same scheme:

- daily backup at 03:30 UTC; weekly prune + `check`, Sundays 04:30. Timers are
  `Persistent=true`, so missed runs catch up after boot. Pruning is kept off
  the daily run so a long prune cannot delay it.
- retention 7 daily / 4 weekly / 12 monthly / 10 yearly, grouped by host only,
  so snapshots from before a path-set change age out normally.
- services contribute their own paths, excludes and pre-backup hooks; a failing
  hook aborts the backup — better a red unit than a snapshot of stale dumps.
- PostgreSQL contributes a hook that dumps the globals plus every database
  (custom format); the live cluster is never backed up. App databases need no
  hook of their own.

## Onboarding a host

1. B2 key, restricted to the bucket and the `<hostname>/` prefix. The prefix
   **must** match the repository path: renaming a host means a new key and a
   new repository. The master key needs `writeKeys` and `listBuckets`.

   ```sh
   B2_APPLICATION_KEY_ID=... B2_APPLICATION_KEY=... \
     scripts/b2-create-restic-key.sh <hostname>
   ```

2. A repository password, `openssl rand -base64 32`. Keep a copy **outside**
   this repo, together with the B2 key — neither is in the backup, and losing
   the password means losing the backups.
3. Store both:
   - rhea: `agenix -e secrets/restic-password.age`, and
     `agenix -e secrets/restic-env.age` holding
     `AWS_ACCESS_KEY_ID=<applicationKeyId>` and
     `AWS_SECRET_ACCESS_KEY=<applicationKey>`. Then `just switch` and
     `systemctl start restic-backups-rhea` (the first run inits the repository).
   - fleet: `backup_b2_account_id`, `backup_b2_account_key` and
     `backup_restic_password` in the host's vaulted inventory vars.

The bucket's lifecycle rule must be "Keep only the last version", otherwise
pruned data lingers as hidden versions and is billed forever.

## rhea

| Unit                                | Does                           |
| ----------------------------------- | ------------------------------ |
| `restic-backups-rhea.service`       | prepare hooks, then `backup`   |
| `restic-backups-rhea-prune.service` | `forget --prune`, then `check` |

`forget` runs with the prune; restic's repository lock keeps the two jobs from
colliding. A failure of either unit pushes an ntfy notification
(`mhnet.notify`).

The path set is `/nix/persist` minus the journal, restic's cache
(`/nix/persist/var/cache`) and the live PostgreSQL cluster. `/bulk`, `/boot` and
`/boot2` are not backed up. Modules add their own:

```nix
mhnet.backup = {
  paths = [ "/var/lib/myapp" ];
  exclude = [ "/var/lib/myapp/cache" ];
  prepare = ''
    ${pkgs.myapp}/bin/myapp dump > /nix/persist/var/backups/myapp.sql
  '';
};
```

`prepare` snippets are concatenated into one script, run as root under
`set -euo pipefail`. Use absolute store paths: the unit's `PATH` holds little
more than coreutils. PostgreSQL dumps go to `/nix/persist/var/backups/postgresql/`.

`restic-rhea` wraps restic with the repository and credentials set:

```sh
sudo restic-rhea snapshots
sudo restic-rhea ls latest /nix/persist/etc
sudo restic-rhea unlock              # after a killed run left a stale lock
```

## Fleet

Roles drop files into `/etc/backup/`: `paths.d/*.txt` (one path per line, no
globs), `exclude.d/*.txt`, and `pre.d/*.sh` hooks, run in lexical order.
PostgreSQL dumps go to `/var/backups/postgresql`. `forget` runs with the daily
backup, both timers with up to 30 minutes of random delay, and a lock keeps the
jobs apart.

`backup-run` wraps restic with the credentials from `/etc/backup/backup.env`:
`backup-run snapshots`, `backup-run restore ...`. A failed backup shows up
through the `FailedUnits` alert (`docs/monitoring.md`).

## Restoring

Always to a scratch location first (fleet: `backup-run` in place of
`restic-rhea`):

```sh
sudo restic-rhea restore latest --target /bulk/restore \
  --include /nix/persist/home/mh/somefile
```

A PostgreSQL database, from the restored dumps:

```sh
sudo -u postgres psql -f globals.sql                       # roles first
sudo -u postgres pg_restore -d myapp --clean --if-exists myapp.dump
```

On rhea, then `just switch` to re-apply the app passwords: `globals.sql`
restores the roles, but the module owns their passwords
(`docs/postgresql.md`).

Bare metal (rhea): rebuild per `docs/bootstrap.md`, then restore `/nix/persist`
before the first `nixos-rebuild switch`.
