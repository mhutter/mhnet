# mhnet

Personal infrastructure: `rhea`, a Hetzner dedicated server running NixOS, and
a fleet of cheap VPS managed with Ansible. `just --list` shows the day-to-day
recipes for both.

`flake.nix`, `nixos/`, `modules/` and `services/` are `rhea`'s configuration;
`ansible/` holds the inventory, playbooks and roles for the fleet. The details
are in `docs/`:

- [bootstrap](docs/bootstrap.md) — rhea: hardware and disk layout, installing
  from scratch, verifying the result, replacing a disk, editing secrets
- [backup](docs/backup.md) — restic to Backblaze B2 for every host: onboarding,
  contributing paths and hooks, restoring
- [monitoring](docs/monitoring.md) — the hub on rhea, push agents on every
  host, alerting
- [postgresql](docs/postgresql.md) — per-app databases on rhea (peer vs.
  password auth, rotating passwords) and the fleet role with its tuning
- [proxy](docs/proxy.md) — rhea's Caddy: publishing an app under a hostname,
  TLS and ACME, per-host IP allowlists
- [updates](docs/updates.md) — rhea's unattended upgrades and their schedule,
  failure and heartbeat alerting, garbage collection, recovering a bad one
- [cloudflared](docs/cloudflared.md) — fleet tunnels: exposing an app hostname
  from a role, required inventory vars
- [firefly](docs/firefly.md) — Firefly III on the fleet: sizing, upgrades,
  importing statements
