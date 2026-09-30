# Updates

Unattended, scheduled so the risky moment happens when someone is awake
(`nixos/auto-upgrade.nix`).

| When                      | What                                                                                                              |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Tue 04:00 UTC             | GitHub Actions `update-lock`: `nix flake update`, build, push `flake: bump inputs` to `main`                      |
| Wed 06:00 UTC (+0–10 min) | `nixos-upgrade`: `nixos-rebuild boot` from `github:mhutter/mhnet`, then `switch`, or reboot if the kernel changed |
| Thu 02:00 UTC (+0–30 min) | `nix-gc --delete-older-than 90d`                                                                                  |

`nixpkgs` follows a release branch, so updates are backports and security
fixes. The day between bump and deploy leaves time to revert a bad bump.

**`main` is the source of truth.** `just` deploys the working tree;
`nixos-upgrade` deploys `main`. Anything not committed **and pushed** is
reverted at the next upgrade.

## Alerting

| Signal                 | Channel                                                             |
| ---------------------- | ------------------------------------------------------------------- |
| A wired unit failed    | ntfy push, high priority, with the last 30 journal lines            |
| The system is degraded | the heartbeat pings Healthchecks' `/fail`, listing the failed units |
| The host is gone       | no heartbeat; Healthchecks alerts after its grace period            |

Wire a unit with `mhnet.notify.units = [ "myservice.service" ];`
(`modules/notify.nix`). The heartbeat runs every 5 minutes
(`mhnet.notify.interval`) and must stay out of `units` — its failure is the
silence. It is also the only reason an unattended reboot is acceptable.

Setup, once — the flake does not evaluate without both secrets:

```sh
agenix -e secrets/ntfy-url.age          # https://ntfy.sh/<unguessable-topic>
agenix -e secrets/healthchecks-url.age  # https://hc-ping.com/<uuid>
```

The ntfy topic name is the password; subscribe to it in the phone app. In
Healthchecks, set a period above the ping interval and a grace that covers a
reboot. The workflow needs only the default `GITHUB_TOKEN`.

## When it goes wrong

- **Did not come back up.** Robot → Rescue, or KVM for the boot menu, and pick
  the generation below the newest (10 kept; `editor = false`, so the menu is the
  only lever). See `docs/bootstrap.md`.
- **Activation failed, host up.** `journalctl -u nixos-upgrade`, then
  `nixos-rebuild switch --rollback`, or fix and `just switch`.
- **Pause updates.** `systemctl stop nixos-upgrade.timer` lasts until the next
  activation or reboot; for longer, `system.autoUpgrade.enable = false` and
  deploy.
- **Release upgrade** (26.05 → 26.11) is never automatic: bump `nixpkgs.url`,
  read the release notes, `just dry`, deploy and watch.

## Garbage collection

One generation a week and 90 days of retention keep about thirteen — more than
the ten boot entries, so every entry has a closure behind it. The store is
deduplicated by `auto-optimise-store`.
