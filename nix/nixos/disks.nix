{ ... }:
let
  vg = "vgpool";

  # Each disk carries its own plain FAT32 ESP. They are kept identical by
  # rsync on every bootloader install (nixos/boot.nix), not by the kernel:
  # bootctl refuses an ESP that is not a GPT partition, so mirroring the ESP
  # with mdadm is not an option.
  diskLayout = device: espMountpoint: espMountOptions: {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            # UEFI wants FAT32 on fixed media; mkfs.fat would pick FAT16 at 2G.
            extraArgs = [
              "-F"
              "32"
            ];
            mountpoint = espMountpoint;
            mountOptions = [ "umask=0077" ] ++ espMountOptions;
          };
        };
        pv = {
          size = "100%";
          type = "8E00"; # Linux LVM; disko would default to 8300
          content = {
            inherit vg;
            type = "lvm_pv";
          };
        };
      };
    };
  };
in
{
  disko.devices = {
    disk = {
      # Both ESPs are nofail: losing either disk must not drop the boot into
      # emergency mode. An unmounted /boot cannot go unnoticed - the
      # systemd-boot builder runs findmnt on it and fails the rebuild.
      nvme0 = diskLayout "/dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103CT7RM" "/boot" [ "nofail" ];
      nvme1 = diskLayout "/dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103LT7RM" "/boot2" [ "nofail" ];
    };

    lvm_vg.${vg} = {
      type = "lvm_vg";
      # disko creates LVs in ascending priority order (default 1000 for all).
      lvs = {
        # raid1 needs free extents on BOTH PVs, so create it before the linear
        # LV rather than leaving it whatever lvbulk did not take.
        lvnix = {
          priority = 100;
          size = "200G";
          lvm_type = "raid1";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/nix";
            mountOptions = [ "noatime" ];
          };
        };
        # linear, spans both PVs, no redundancy
        lvbulk = {
          priority = 200;
          size = "1500G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/bulk";
            mountOptions = [
              "noatime"
              "nofail"
            ];
          };
        };
      };
    };

    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "defaults"
        "size=16G"
        "mode=0755"
      ];
    };
  };
}
