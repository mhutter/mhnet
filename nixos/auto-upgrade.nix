{ ... }:
{
  ## Unattended updates
  # nixpkgs is pinned to a release branch, so what lands here is backports and
  # security fixes, not a moving target. The 26.05 -> 26.11 jump stays manual.
  #
  # Note the source: the flake ref, NOT the rsync'd working tree that `just`
  # deploys to ${remote_dir}. Whatever is on main wins, so uncommitted state
  # left on the host is silently reverted by the next run.
  system.autoUpgrade = {
    enable = true;
    flake = "github:mhutter/mhnet";
    operation = "switch";

    # A no-op for flake systems — nixos-rebuild only warns. The lock is bumped
    # in CI instead, see .github/workflows/update-lock.yml.
    upgrade = false;

    # Reboot only when the kernel or initrd actually changed, and only inside
    # the window. Without this a new kernel sits as the boot default, unbooted,
    # until some unplanned reboot weeks later — that latency is the failure
    # mode this whole setup exists to avoid.
    allowReboot = true;
    rebootWindow = {
      lower = "05:30";
      upper = "08:00";
    };

    # Wednesday, so someone is awake and off the train when it comes back up,
    # and never a Friday. Clear of the 03:30 backup and the Sunday 04:30 prune.
    dates = "Wed *-*-* 06:00:00";
    randomizedDelaySec = "10min";

    # A missed run waits for next Wednesday rather than catching up. A catch-up
    # run outside the reboot window still executes `nixos-rebuild boot`, which
    # would leave an un-booted kernel as the default — exactly what
    # rebootWindow exists to prevent.
    persistent = false;

    # GC gets its own schedule below. Leaving this off also keeps
    # nixos-upgrade's OnSuccess= free, which the module would otherwise claim
    # and collide with the notify wiring.
    runGarbageCollection = false;
  };

  mhnet.notify.units = [ "nixos-upgrade.service" ];

  ## Garbage collection
  # /nix is 200G, and unattended rebuilds grow the store without bound. At
  # roughly one generation a week, 90d keeps ~13 — comfortably more than
  # boot.loader.systemd-boot.configurationLimit (10), so every entry the boot
  # menu still offers has a closure to boot into. Deduplication is already
  # handled by nix.settings.auto-optimise-store.
  nix.gc = {
    automatic = true;
    dates = "Thu *-*-* 02:00:00";
    options = "--delete-older-than 90d";
    randomizedDelaySec = "30min";
    persistent = true;
  };
}
