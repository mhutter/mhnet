{
  lib,
  utils,
  persist,
  ...
}:
let
  # These are in utils.pathsNeededForBoot, so impermanence bind-mounts them in
  # the INITRD (before initrd-nixos-activation.service) rather than in stage 2.
  # Nothing creates the bind *source* that early: nixos-install only runs
  # `switch-to-configuration boot`, which never calls the activation script, and
  # impermanence's own createPersistentStorageDirs runs inside
  # initrd-nixos-activation, i.e. after these mounts. Without the tmpfiles rules
  # below the mounts fail silently and the state is simply not persisted.
  bootCritical = [
    "/var/log"
    "/var/lib/nixos"
  ];
in
{
  ## Configuration of various storage locations
  environment.etc."machine-id".source = "${persist}/etc/machine-id";

  ## Bind-Mounts
  environment.persistence.${persist} = {
    directories = [
      "/var/log" # journal (boot-critical, see above)
      "/var/lib/nixos" # uid/gid allocation map (boot-critical, see above)
      "/var/lib/systemd/timers" # Persistent=true stamp files
      "/var/lib/systemd/timesync" # clock bump before NTP responds
    ];
    files = [ ];
  };

  # Create the bind sources in the initrd. systemd-tmpfiles-setup-sysroot runs
  # with --prefix=/sysroot, hence the /sysroot-prefixed paths.
  boot.initrd.systemd.tmpfiles.settings."10-persist" = lib.listToAttrs (
    map (
      dir:
      lib.nameValuePair "/sysroot${persist}${dir}" {
        d = {
          mode = "0755";
          user = "root";
          group = "root";
        };
      }
    ) bootCritical
  );

  # ...and order it before the mounts. Both are only WantedBy=initrd.target with
  # no mutual ordering, so this has to be spelled out.
  boot.initrd.systemd.services.systemd-tmpfiles-setup-sysroot.before = map (
    dir: "${utils.escapeSystemdPath "/sysroot${dir}"}.mount"
  ) bootCritical;
}
