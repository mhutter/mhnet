# Bootstrap

NixOS 26.05 on a Hetzner dedicated server: UEFI, tmpfs root, one ESP per disk,
both NVMes in one LVM volume group (`nixos/disks.nix`).

| Volume          | Layout | Size   | Mount    |
| --------------- | ------ | ------ | -------- |
| `nvme0n1p1`     | plain  | 2 G    | `/boot`  |
| `nvme1n1p1`     | plain  | 2 G    | `/boot2` |
| `vgpool/lvnix`  | RAID1  | 200 G  | `/nix`   |
| `vgpool/lvbulk` | linear | 2048 G | `/bulk`  |

The ESPs are plain FAT32, not an mdadm mirror: `bootctl` rejects an ESP that is
not a GPT partition, which breaks `nixos-install`, every `nixos-rebuild` and
`systemd-boot-random-seed.service`. `bootctl` writes `/boot`;
`extraInstallCommands` rsyncs it to `/boot2`, so either disk boots on its own.

`/` is a 16 G tmpfs, wiped on boot. State moves to `/nix/persist` through native
options (`services.openssh.hostKeys`, `users.users.<name>.home`, …);
`impermanence` covers only what has none (`nixos/persistence.nix`).

## Installing

### 1. Rescue system → kexec installer

In Robot, activate **Rescue → Linux64** and reset the server, then:

```sh
curl -L https://github.com/nix-community/nixos-images/releases/download/nixos-26.05/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  | tar -xzf- -C /root
/root/kexec/run
```

Reconnect as `root` on port 22 once SSH drops.

### 2. Preflight

After the reboot root login is off and SSH moves to port 50642, so a mismatch
here means a KVM trip:

```sh
[ -d /sys/firmware/efi/efivars ] && echo "UEFI ok" || echo "BIOS — STOP"
ls /sys/firmware/efi/efivars | head   # must be non-empty and writable
efibootmgr -v                         # record the pre-existing entries

ip -br link                           # must show enp35s0  (nixos/network.nix)
ip -br addr; ip route; ip -6 route    # must match nixos/network.nix

ls -l /dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103CT7RM \
      /dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103LT7RM
```

If `efivars` is missing or read-only (it does not always survive kexec), set
`canTouchEfiVariables = false` in `nixos/boot.nix`. Only the NVRAM entry is
skipped; the removable fallback `\EFI\BOOT\BOOTX64.EFI` is written either way.

### 3. Upload the config

```sh
rsync -a --delete --exclude .git --exclude .direnv \
  --exclude .env --exclude .vaultpass --exclude /ansible \
  ~/code/mhnet/ root@rhea.mhnet.dev:/root/nixos-config/
```

`flake.lock` must be included — it pins disko.

### 4. Partition and format

```sh
export NIX_CONFIG='experimental-features = nix-command flakes'

script=$(nix build --no-link --print-out-paths \
  /root/nixos-config#nixosConfigurations.rhea.config.system.build.destroyFormatMount)
"$script"/bin/disko-destroy-format-mount --yes-wipe-all-disks

lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPENAME,MOUNTPOINT
lvs -a -o+lv_layout,devices vgpool    # lvnix: raid1, rimages on different PVs
findmnt -R /mnt                       # /mnt/boot and /mnt/boot2, both vfat
```

### 5. Seed persistent state

Before `nixos-install`: it never runs the activation script, so nothing else
creates these.

```sh
install -d -m 0755 /mnt/nix/persist/etc/ssh
systemd-id128 new > /mnt/nix/persist/etc/machine-id
chmod 0444 /mnt/nix/persist/etc/machine-id

# also the agenix identity
ssh-keygen -t ed25519 -N "" -C rhea -f /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key
chmod 0600 /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key

install -d -m 0755 /mnt/nix/persist/var/log /mnt/nix/persist/var/lib/nixos

cat /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key.pub
```

Put the public key into `secrets.nix` as `rhea = "ssh-ed25519 … rhea";`, rekey
(`agenix -r`) and repeat step 3: the host decrypts its secrets with this key.
When rebuilding from a backup, restore the old key instead
(`/nix/persist/etc/ssh`, `docs/backup.md`) and skip the rekey.

### 6. Install and check the bootloader

```sh
nixos-install --flake /root/nixos-config#rhea --no-root-password

bootctl --esp-path=/mnt/boot status
ls -l /mnt/boot/EFI/systemd/systemd-bootx64.efi \
      /mnt/boot/EFI/BOOT/BOOTX64.EFI       # the fallback — do not reboot without it
diff -r -x random-seed /mnt/boot /mnt/boot2
```

`bootctl` creates one NVRAM entry, for nvme0. Add nvme1's by hand:

```sh
efibootmgr -c -d /dev/nvme1n1 -p 1 \
  -L "Linux Boot Manager (nvme1)" \
  -l '\EFI\systemd\systemd-bootx64.efi'
efibootmgr -v                              # both entries, check BootOrder
```

### 7. Reboot

```sh
sync; reboot
```

Rescue, kexec and installed system all have different host keys:

```sh
ssh-keygen -R rhea.mhnet.dev
ssh-keygen -R 116.202.233.38
ssh-keygen -R '[rhea.mhnet.dev]:50642'
ssh -p 50642 mh@rhea.mhnet.dev             # compare against step 5
```

## Verifying

```sh
systemctl --failed                         # must be empty
journalctl -b -u sysroot-var-log.mount -u sysroot-var-lib-nixos.mount
for m in /nix /bulk /boot /boot2 /var/log /var/lib/nixos; do
  findmnt -no TARGET,SOURCE,FSTYPE "$m" || echo "MISSING: $m"
done
findmnt -t tmpfs /                         # size=16G
lvs -a -o+lv_layout,devices vgpool
bootctl status
diff -r -x random-seed /boot /boot2
efibootmgr -v
readlink -f /etc/machine-id                # /nix/persist/etc/machine-id
```

`/boot/loader/random-seed` is rewritten on every boot and deliberately not
synced, hence `-x random-seed`.

**Reboot test.** `touch ~/canary`, reboot. `~/canary` must survive,
`journalctl --list-boots` must show more than one boot, `/etc/machine-id` must
be unchanged.

**Single-disk boot test** (KVM). With the ESPs in sync, boot with one NVMe
disabled, once per disk. Both must reach a login prompt, with one ESP missing
(both are `nofail`), `/nix` on its surviving raid1 leg, and `/bulk` gone when
its disk is. Afterwards restore the boot order and wait for `lvnix` to resync.

## Replacing a disk

Re-run disko for that disk (or `sgdisk`/`mkfs.vfat` by hand), then
`nixos-rebuild boot` — nothing repopulates the new ESP on its own. Check the
output for the rsync warning, then `diff -r -x random-seed /boot /boot2`.

## Secrets

agenix, keyed on the host key from step 5. From the devShell:
`agenix -e secrets/<name>.age`, and `agenix -r` after changing recipients in
`secrets.nix`.
