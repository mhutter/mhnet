# mhnet

Personal infrastructure: `rhea`, a Hetzner dedicated server running NixOS, and
a fleet of cheap VPS managed with Ansible. `just --list` shows the day-to-day
recipes for both.

## NixOS — rhea

`flake.nix`, `nixos/`, `modules/` and `services/` are `rhea`'s configuration;
the details are in `docs/`:

- [bootstrap](docs/bootstrap.md) — hardware and disk layout, installing from
  scratch, verifying the result, replacing a disk, editing secrets
- [backup](docs/backup.md) — restic to Backblaze B2: what is backed up, how
  modules contribute paths and pre-backup hooks, restoring
- [postgresql](docs/postgresql.md) — declaring per-app databases and roles,
  peer vs. password auth, rotating passwords
- [proxy](docs/proxy.md) — Caddy: publishing an app under a hostname, TLS and
  ACME, per-host IP allowlists
- [updates](docs/updates.md) — unattended upgrades and their schedule, failure
  and heartbeat alerting, garbage collection, recovering a bad one

## Ansible — the VPS fleet

`ansible/` holds the inventory, playbooks and roles for the fleet; the details
are in `ansible/docs/`:

- [backup](ansible/docs/backup.md) — restic to Backblaze B2: how roles
  contribute paths and hooks, onboarding a host, restoring
- [cloudflared](ansible/docs/cloudflared.md) — tunnels: exposing an app
  hostname from a role, required inventory vars
- [postgresql](ansible/docs/postgresql.md) — the shared server, its tuning,
  declaring a per-app database
- [monitoring](ansible/docs/monitoring.md) — VictoriaMetrics/VictoriaLogs and
  Grafana on the hub, push agents on every host, alerting
- [silverbullet](ansible/docs/silverbullet.md) — multiple SilverBullet spaces
  on one host
- [firefly](ansible/docs/firefly.md) — Firefly III, its sizing, upgrades, and
  importing statements
