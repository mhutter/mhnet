# rhea configuration

NixOS configuration for `rhea`, a Hetzner dedicated server. `just --list` shows
the day-to-day recipes; everything else is in `docs/`:

- [bootstrap](docs/bootstrap.md) — hardware and disk layout, installing from
  scratch, verifying the result, replacing a disk, editing secrets
- [backup](docs/backup.md) — restic to Backblaze B2: what is backed up, how
  modules contribute paths and pre-backup hooks, restoring
- [postgresql](docs/postgresql.md) — declaring per-app databases and roles,
  peer vs. password auth, rotating passwords
