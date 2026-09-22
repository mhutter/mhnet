# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Host

`rhea` — Hetzner dedicated, 24-core AMD, 128 GB RAM, 2× 1.92 TB NVMe. NixOS
26.05, one flake output: `nixosConfigurations.rhea` (x86_64-linux). Inputs:
agenix, disko, impermanence.

## Commands

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

## Layout

- `flake.nix` — passes `specialArgs` (`username`, `sshPublicKeys`, `persist`);
  modules take these as plain function args, not via `config`.
- `nixos/` — host base. `nixos/default.nix` is the single import list for
  everything, including `modules/` and `services/`.
- `modules/` — cross-cutting `mhnet.*` options.
- `services/` — one file per service.
- `secrets/*.age`, `secrets.nix` — agenix; the age identity is the SSH host key.
- `docs/` — `bootstrap.md` (install, verification, disk replacement),
  `backup.md`, `postgresql.md`.

## Before editing

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
- **Deliberate, not gaps:** no swap or zram, and unallocated VG space left as
  growth headroom for both mounts.

## Conventions

- Nix: nixfmt-rfc-style, matched by hand — no `formatter` output, nixfmt is not
  installed locally.
- Markdown: `prettier`.
- `##` marks section comments, `#` explains _why_ a non-obvious choice was made.
  The comment density is intentional — keep it, but keep it terse.
- Commits: short imperative subject, optional `area: ` prefix, `git commit -s`.
