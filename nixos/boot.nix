{ pkgs, ... }:
{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        # 2G ESP, one kernel + systemd initrd per generation
        configurationLimit = 10;
        # Headless: no kernel cmdline editing from the console
        editor = false;
        # bootctl only ever touches /boot. /boot2 is the second disk's ESP and
        # is kept identical here, so either disk can boot on its own. Runs
        # after every bootloader install, i.e. on install and on
        # `nixos-rebuild boot/switch`.
        #
        # loader/random-seed is excluded: systemd-boot rewrites it on every
        # boot (and so does systemd-boot-random-seed.service), so it would
        # make the two ESPs differ within one boot no matter what is synced
        # here, and a copied seed is a seed used twice. --delete-excluded
        # keeps a stale copy from lingering on /boot2.
        extraInstallCommands = ''
          if ${pkgs.util-linux}/bin/findmnt /boot2 >/dev/null; then
            ${pkgs.rsync}/bin/rsync -a --delete --delete-excluded \
              --exclude=/loader/random-seed /boot/ /boot2/
          else
            echo "WARNING: /boot2 is not mounted, the second ESP was NOT updated" >&2
          fi
        '';
      };
      efi = {
        # Only controls whether `bootctl install` may write the NVRAM boot
        # entry. Requires a writable efivarfs at install time, which is NOT
        # guaranteed after kexec - check before installing (see README).
        # Note the removable fallback /EFI/BOOT/BOOTX64.EFI is written by
        # bootctl either way, and is what survives losing a disk.
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };

    initrd = {
      availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "xhci_pci"
      ];

      # dm-raid drives lvnix; it uses md's raid1 personality.
      kernelModules = [
        "dm-mod"
        "dm-raid"
        "raid1"
      ];
      services.lvm.enable = true;
    };
  };
}
