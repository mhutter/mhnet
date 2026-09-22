# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Two halves, one repo: `rhea` is a NixOS host at the repo root, everything under
`ansible/` is the VPS fleet. Ansible-managed services move to NixOS over time,
so expect a role and a module to describe the same thing for a while.

## Guidelines

Most hosts are very cheap VPS, paid out of the user's own pocket, so being
conservative with sizing is a must. The user is the sole consumer of most of
these systems, so performance is rarely the issue.

Systems should be low-maintenance — no manual intervention to stay up to date —
and secure by default: automated updates, minimal permissions, regular backups.

- dependencies (e.g. databases) co-located on the same system
- exposing HTTP services via cloudflared -> no incoming connections required
- lean setups: prefer built-in (e.g. sqlite) vs separate databases; prefer
  native installations vs containers
- Ubuntu (the latest LTS release, currently 26.04 "Resolute Raccoon") is the
  default operating system for the Ansible fleet

## NixOS — rhea

`rhea` — Hetzner dedicated, 24-core AMD, 128 GB RAM, 2× 1.92 TB NVMe. NixOS
26.05, one flake output: `nixosConfigurations.rhea` (x86_64-linux). Inputs:
agenix, disko, impermanence.

| Command       | Effect                                          |
| ------------- | ----------------------------------------------- |
| `just`        | list recipes                                    |
| `just sync`   | rsync the working tree to the host (no rebuild) |
| `just dry`    | evaluate and build only                         |
| `just build`  | build, no activation                            |
| `just test`   | activate now, reverted by a reboot              |
| `just boot`   | make it the boot default, no activation         |
| `just switch` | activate **and** make it the boot default       |

Secrets, inside direnv / `nix develop`: `agenix -e secrets/<name>.age`,
`agenix -r` to rekey after changing recipients in `secrets.nix`.

- Every recipe rsyncs the working tree (uncommitted included) to the host and
  runs `nixos-rebuild` over SSH **there** — nothing is evaluated or built
  locally, so there is no local build/test loop.
- **Do not deploy while working on code.** `switch`/`boot`/`test`/`build` are
  the user's call; run them only when asked.
- No test suite. `just dry` is the check — again, only when asked.

### Layout

- `flake.nix` — passes `specialArgs` (`username`, `sshPublicKeys`, `persist`);
  modules take these as plain function args, not via `config`.
- `nixos/` — host base. `nixos/default.nix` is the single import list for
  everything, including `modules/` and `services/`.
- `modules/` — cross-cutting `mhnet.*` options.
- `services/` — one file per service.
- `secrets/*.age`, `secrets.nix` — agenix; the age identity is the SSH host key.
- `docs/` — `bootstrap.md` (install, verification, disk replacement),
  `backup.md`, `postgresql.md`, `updates.md`.
- `.github/workflows/update-lock.yml` — the only thing that bumps `flake.lock`.

### Before editing

- **tmpfs root.** `/` is wiped on boot; state belongs under `${persist}`. Prefer
  a native NixOS option (`dataDir`, `hostKeys`, `users.users.<n>.home`, …); use
  `environment.persistence` only when none exists. `/var/log` and
  `/var/lib/nixos` are boot-critical and bind-mounted in the initrd —
  `nixos/persistence.nix`.
- **Dual ESP.** `/boot` + `/boot2`, plain FAT32, kept identical by rsync on every
  bootloader install (`nixos/boot.nix`). Not mdadm: `bootctl` rejects an ESP that
  is not a GPT partition.
- **`mhnet.backup`** (`modules/backup.nix`) — modules contribute `paths`,
  `exclude`, `prepare`. `prepare` is `lines`, runs as root under
  `set -euo pipefail` before the backup; a failing hook aborts it by design. Use
  absolute store paths. The restic repository path embeds the hostname and must
  match the B2 key prefix — renaming the host breaks access.
- **`mhnet.postgresql.apps`** (`services/postgresql.nix`) — the attribute name is
  role, database and owner at once. Adding a `passwordFile` switches the app from
  peer to `scram-sha-256` with no fallback (`pg_hba` is first-match-wins).
  Passwords are applied out of band by generated
  `postgresql-password-<app>.service` units, never via the nix store. Removing an
  app drops nothing. PostgreSQL contributes its own backup hook (dumps, not the
  live cluster), so app modules need none.
- **`mhnet.notify`** (`modules/notify.nix`) — modules append unit names to
  `units` to get an `OnFailure=` ntfy push. The hourly Healthchecks heartbeat is
  the dead-man switch and must stay out of `units`: its failure is already
  reported by the silence it causes.
- **`system.autoUpgrade`** (`nixos/auto-upgrade.nix`) — deploys `main` from the
  forge on a timer, **not** the working tree `just` rsyncs over. Uncommitted
  state on the host is reverted at the next run. `docs/updates.md`.
- **Deliberate, not gaps:** no swap or zram, and unallocated VG space left as
  growth headroom for both mounts.

## Ansible — the VPS fleet

Hostname scheme: `<provider>-<purpose>`, e.g. `scw-miniflux`. Provider is a
short code (`scw` = Scaleway, `hbc` = Hetzner Cloud, `ovh` = OVH, ...); purpose
is the primary app/role name, lowercase. Append `-2`, `-3`, ... only if a
provider ends up hosting more than one instance of the same purpose.

```sh
ansible-playbook ansible/playbooks/site.yml                 # full run
ansible-playbook ansible/playbooks/site.yml --tags miniflux # single role
just bootstrap                                              # bootstrap a new host
ansible-vault edit ansible/inventory/hosts.yml              # edit secrets
```

### Layout

- `ansible.cfg` — stays at the repo root, so `ansible-playbook` finds it when
  run from there; its `inventory` and `roles_path` point into `ansible/`
- `ansible/inventory/hosts.yml` — fully Ansible Vault-encrypted; hosts, groups,
  and all vars (secrets included) live here
- `ansible/inventory.example.yml` — unencrypted skeleton of the above,
  documenting every required var; keep in sync when roles gain inventory vars
- `ansible/roles/` — `common`, `firewall`, `backup`, `cloudflared`,
  `postgresql`, `dns64`, `monitoring_agent` apply broadly; `pocket_id`,
  `miniflux`, `silverbullet`, `firefly`, `monitoring_hub` are per-app
- `ansible/playbooks/site.yml` — main playbook, run against `all` plus per-app
  host groups; roles are tagged with their own name for selective runs
- `ansible/playbooks/bootstrap.yml` — minimal `common`-only pass for brand-new
  hosts
- `ansible/docs/` — one file per role that needs explaining (`backup`,
  `cloudflared`, `postgresql`, `monitoring`, `silverbullet`, `firefly`),
  linked from `README.md`
- `scripts/` — shared with the NixOS half; `b2-create-restic-key.sh` mints the
  per-host B2 key both backup implementations use
- `.vaultpass` — local vault password file (gitignored), used by
  `ansible.cfg`/`ansible-vault`

See `ansible/docs/` for details on those roles (onboarding a host, required
vars, manual operations).

## Secrets

Two systems, deliberately separate: agenix for `rhea` (recipients in
`secrets.nix`, the age identity is the host's SSH key) and Ansible Vault for
the fleet inventory. Neither can reach the other's hosts.

Never generate secrets, edit vaulted inventory values, or print decrypted
vault contents yourself — hand these to the user with the exact command to
run (e.g. `ansible-vault edit ansible/inventory/hosts.yml`, `openssl rand
-base64 32`).

## Conventions

- Nix: nixfmt-rfc-style, matched by hand — no `formatter` output, nixfmt is not
  installed locally.
- Markdown: `prettier`.
- `##` marks section comments, `#` explains _why_ a non-obvious choice was made.
  The comment density is intentional — keep it, but keep it terse.
- Commits: short imperative subject, optional `area: ` prefix, `git commit -s`.
