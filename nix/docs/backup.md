# Backups

restic to Backblaze B2, configured in `modules/backup.nix` on top of the
nixpkgs `services.restic.backups` module. Same bucket and layout as the mhnet
fleet: one repository per host under `s3:<endpoint>/mhnet-restic/<hostname>`.

| Unit                                | When            | Does                           |
| ----------------------------------- | --------------- | ------------------------------ |
| `restic-backups-rhea.service`       | daily 03:30 UTC | prepare hooks, then `backup`   |
| `restic-backups-rhea-prune.service` | Sun 04:30 UTC   | `forget --prune`, then `check` |

Both timers are `Persistent=true`, so a missed run catches up after boot
(`/nix/persist/var/lib/systemd/timers` holds the stamps). Retention is 7 daily /
4 weekly / 12 monthly / 10 yearly, grouped by host only — snapshots taken before
a path-set change age out normally instead of being kept forever.

Forget and prune deliberately do **not** run with the daily backup: a long prune
must not delay it. They are an hour apart; restic's own repository lock is what
keeps them from colliding if the backup overruns.

## What gets backed up

`/` is a tmpfs, so the default path set is just `/nix/persist`, minus:

- `/nix/persist/var/log` — journal
- `/nix/persist/var/cache` — restic's own cache, moved there from the module's
  `/var/cache` default so it survives a reboot instead of dying with the tmpfs
  root and forcing the next run to re-fetch the repository index
- `/nix/persist/var/lib/postgresql` — the live cluster; dumps go instead
  (below)

`/bulk` is **not** backed up. `/boot` and `/boot2` are not either — they are
rebuilt by `nixos-rebuild boot`.

## Contributing paths and hooks

Service modules declare their own, merged across the whole configuration:

```nix
mhnet.backup = {
  paths = [ "/var/lib/myapp" ];
  exclude = [ "/var/lib/myapp/cache" ];
  prepare = ''
    ${pkgs.myapp}/bin/myapp dump > /nix/persist/var/backups/myapp.sql
  '';
};
```

`prepare` is `lines`, so every module's snippet is concatenated into one script
that runs as root under `set -euo pipefail` before the backup. A failing hook
aborts the backup — better a red unit than a snapshot full of stale dumps. Use
absolute store paths: the unit's `PATH` holds little more than coreutils.

PostgreSQL already contributes one (`services/postgresql.nix`): it dumps the
globals plus every database in custom format to
`/nix/persist/var/backups/postgresql/` and excludes the live cluster. App
modules need no database hook of their own.

## Setup

### 1. B2 application key

The key is restricted to the `mhnet-restic` bucket and the `rhea/` file name
prefix. Its prefix **must** match the repository path, so renaming the host
means a new key and a new repository.

```sh
cd ~/code/mhnet
B2_APPLICATION_KEY_ID=... B2_APPLICATION_KEY=... \
  scripts/b2-create-restic-key.sh rhea
```

The master key needs `writeKeys` and `listBuckets`. The bucket's lifecycle rule
must be "Keep only the last version", otherwise pruned data lingers as hidden
versions and is billed forever.

### 2. Secrets

Two agenix secrets, already declared in `secrets.nix`. From the devShell:

```sh
# repository encryption password — keep a copy OUTSIDE this repo,
# losing it means losing the backups
openssl rand -base64 32
agenix -e secrets/restic-password.age

# the key pair from step 1, as an EnvironmentFile
agenix -e secrets/restic-env.age
```

`restic-env.age` holds exactly:

```sh
AWS_ACCESS_KEY_ID=<applicationKeyId>
AWS_SECRET_ACCESS_KEY=<applicationKey>
```

### 3. Activate

```sh
just switch
systemctl start restic-backups-rhea    # first run also inits the repository
```

## Operating

`restic-rhea` is a wrapper with the repository and credentials already in the
environment — anything restic can do, it can do:

```sh
sudo restic-rhea snapshots
sudo restic-rhea stats latest
sudo restic-rhea ls latest /nix/persist/etc
sudo restic-rhea unlock              # after a killed run left a stale lock
```

Health check:

```sh
systemctl list-timers 'restic-backups-*'
systemctl status restic-backups-rhea restic-backups-rhea-prune
journalctl -u restic-backups-rhea -n 50
```

Nothing alerts on a failed backup yet — the host has no monitoring. Until it
does, `systemctl --failed` is the only signal.

## Restoring

Single file or directory, to a scratch location first:

```sh
sudo restic-rhea restore latest --target /bulk/restore \
  --include /nix/persist/home/mh/somefile
```

A PostgreSQL database, from the dumps:

```sh
sudo restic-rhea restore latest --target /bulk/restore \
  --include /nix/persist/var/backups/postgresql
cd /bulk/restore/nix/persist/var/backups/postgresql

sudo -u postgres psql -f globals.sql                       # roles first
sudo -u postgres pg_restore -d myapp --clean --if-exists myapp.dump
```

Then `just switch` to re-apply the app passwords (see `docs/postgresql.md` —
`globals.sql` restores the roles but the module owns their passwords).

Bare metal: rebuild the host per `docs/bootstrap.md`, then restore
`/nix/persist` before the first `nixos-rebuild switch`. That needs the restic
password and the B2 key, neither of which is in the backup — keep both offsite.
