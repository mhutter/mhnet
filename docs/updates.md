# Updates

Unattended, but on a schedule chosen so that the risky moment happens when
someone is awake.

## The loop

| When                      | What                                                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tue 04:00 UTC             | GitHub Actions `update-lock` runs `nix flake update`, builds the system closure, pushes `flake: bump inputs` to `main`                                        |
| Wed 06:00 UTC (+0–10 min) | `nixos-upgrade.service` runs `nixos-rebuild boot --refresh --flake github:mhutter/rhea`, then `switch` if the kernel is unchanged, or `shutdown -r +1` if not |
| Thu 02:00 UTC             | `nix-gc`, `--delete-older-than 90d`                                                                                                                           |

`nixpkgs` is pinned to a release branch, so what arrives is backports and
security fixes. The day of lead time between the lock bump and the deploy is
there so a bad bump can be reverted before the host takes it.

## Source of truth

`just` deploys the rsync'd working tree. `nixos-upgrade` deploys `main`.
Anything on the host that is not committed **and pushed** is reverted at the
next upgrade — commit before walking away.

## One-off setup

Both secrets must exist or the flake will not evaluate, in CI or on the host:

```sh
agenix -e secrets/ntfy-url.age          # https://ntfy.sh/<unguessable-topic>
agenix -e secrets/healthchecks-url.age  # https://hc-ping.com/<uuid>, no trailing slash
```

An ntfy topic is readable by anyone who knows its name, so treat the name as the
password. Subscribe to it in the phone app.

In Healthchecks, set the check to **period 1h, grace 2h**. The heartbeat pings
hourly (`mhnet.notify.interval`), so roughly three hours of silence is the
alert.

The workflow needs nothing beyond the default `GITHUB_TOKEN`; it declares
`permissions: contents: write` itself.

## What you get told

- **A unit failed** — ntfy push, high priority, carrying the last 30 journal
  lines. Wired through `mhnet.notify.units`: currently `nixos-upgrade` and both
  restic jobs.
- **The system is degraded** — the hourly heartbeat pings `…/fail` instead,
  listing the failed units. Catches anything nobody wired up explicitly.
- **The host is gone** — no ping arrives and Healthchecks alerts after the
  grace period. This is the one ntfy structurally cannot raise, and the only
  reason the reboot is allowed to happen unattended at all.

Add a unit to the first category with:

```nix
mhnet.notify.units = [ "myservice.service" ];
```

## When it goes wrong

- **It did not come back up.** Hetzner Robot → Rescue, or a KVM session for the
  boot menu. systemd-boot keeps `configurationLimit = 10` generations; pick the
  one below the newest. `editor = false`, so the menu is the only lever from
  the console — see [bootstrap](bootstrap.md).
- **Activation failed, host still up.** `journalctl -u nixos-upgrade`, then
  either `nixos-rebuild switch --rollback` or fix it and `just switch`.
- **Pause updates.** `systemctl stop nixos-upgrade.timer` holds only until the
  next activation or reboot re-creates it. To pause for longer, set
  `system.autoUpgrade.enable = false` and deploy.
- **Release upgrade.** 26.05 → 26.11 is never automatic: bump `nixpkgs.url` by
  hand, read the release notes, `just dry`, then deploy and watch.

## Garbage collection

One generation a week means 90 days keeps about thirteen — comfortably more
than the ten entries systemd-boot offers, so every entry the boot menu shows
still has a closure behind it. `/nix` is 200G; deduplication is already handled
by `auto-optimise-store`.
