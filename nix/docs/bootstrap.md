# Initial Setup

NixOS 26.05 on a Hetzner dedicated server. UEFI, tmpfs root, one ESP per disk,
both NVMes in one LVM volume group:

| Volume          | Layout | Size   | Mount    |
| --------------- | ------ | ------ | -------- |
| `nvme0n1p1`     | plain  | 2 G    | `/boot`  |
| `nvme1n1p1`     | plain  | 2 G    | `/boot2` |
| `vgpool/lvnix`  | RAID1  | 200 G  | `/nix`   |
| `vgpool/lvbulk` | linear | 1500 G | `/bulk`  |

The two ESPs are plain FAT32 partitions, not an mdadm mirror: `bootctl` rejects
an ESP that is not a GPT partition (`File system … is not located on a
partitioned block device`), which breaks `nixos-install`, every later
`nixos-rebuild` — it runs `bootctl status` — and
`systemd-boot-random-seed.service`. `bootctl` only ever writes `/boot`;
`boot.loader.systemd-boot.extraInstallCommands` rsyncs it to `/boot2` after
every bootloader install, so either disk can boot on its own.

The root filesystem is a 16 G tmpfs and is wiped on every boot. State is moved
to `/nix/persist` with regular NixOS module options where one exists
(`services.openssh.hostKeys`, `users.users.<name>.home`, `environment.etc`), and
`impermanence` is used only where none does (`/var/log`, `/var/lib/nixos`,
`/var/lib/systemd/{timers,timesync}`).

## Bootstrapping

### 1. Rescue system → kexec installer

In Robot, activate **Rescue → Linux64** and reset the server, then:

```sh
curl -L https://github.com/nix-community/nixos-images/releases/download/nixos-26.05/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  | tar -xzf- -C /root
/root/kexec/run
```

Wait until SSH disconnects, then reconnect as `root` on port 22.

### 2. Preflight — before anything destructive

Every one of these has to match what the configuration assumes:

```sh
[ -d /sys/firmware/efi/efivars ] && echo "UEFI ok" || echo "BIOS — STOP"
ls /sys/firmware/efi/efivars | head   # must be non-empty and writable
efibootmgr -v                         # record the pre-existing entries

ip -br link                           # must show enp35s0  (nixos/network.nix)
ip -br addr; ip route; ip -6 route    # must match nixos/network.nix

ls -l /dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103CT7RM \
      /dev/disk/by-id/nvme-KXD51RUE1T92_TOSHIBA_30NS103LT7RM
```

After the reboot, root login is disabled and SSH moves to port 50642, so a
mismatch here means a KVM trip to recover.

If `efivars` is missing or read-only — EFI runtime services do not always
survive kexec — set `canTouchEfiVariables = false` in `nixos/boot.nix` before
installing. `bootctl` writes the removable fallback `\EFI\BOOT\BOOTX64.EFI`
either way; only the NVRAM entry is skipped.

### 3. Upload the config

From the workstation:

```sh
rsync -a --delete --exclude .git --exclude .direnv \
  ~/code/rhea/ root@rhea.mhnet.dev:/root/nixos-config/
```

`flake.lock` must be included — it is what pins disko.

### 4. Partition and format

Built from `flake.lock`, so the disko CLI and the disko NixOS module are the
same version:

```sh
export NIX_CONFIG='experimental-features = nix-command flakes'

script=$(nix build --no-link --print-out-paths \
  /root/nixos-config#nixosConfigurations.rhea.config.system.build.destroyFormatMount)
"$script"/bin/disko-destroy-format-mount --yes-wipe-all-disks
```

Drop `--yes-wipe-all-disks` to get the "type yes to continue" prompt instead.

Check the result before moving on:

```sh
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPENAME,MOUNTPOINT
lvs -a -o+lv_layout,devices vgpool    # lvnix: raid1, rimages on different PVs
findmnt -R /mnt                       # /mnt/boot and /mnt/boot2, both vfat
```

### 5. Seed persistent state

Has to happen before `nixos-install`: it runs `switch-to-configuration boot`,
which never invokes the activation script, so nothing else creates these.

```sh
install -d -m 0755 /mnt/nix/persist/etc/ssh

# machine-id — /etc/machine-id is a symlink to this path
systemd-id128 new > /mnt/nix/persist/etc/machine-id
chmod 0444 /mnt/nix/persist/etc/machine-id

# ssh host key — also the agenix identity (age.identityPaths follows
# services.openssh.hostKeys)
ssh-keygen -t ed25519 -N "" -C rhea -f /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key
chmod 0600 /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key

# belt and braces — nixos/persistence.nix also creates these in the initrd
install -d -m 0755 /mnt/nix/persist/var/log
install -d -m 0755 /mnt/nix/persist/var/lib/nixos
```

Record the host key for `secrets.nix` and for verifying the first SSH login:

```sh
cat /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /mnt/nix/persist/etc/ssh/ssh_host_ed25519_key.pub
```

Paste the public key into `secrets.nix` as `rhea = "ssh-ed25519 … rhea";`. No
secrets are defined yet, so this does not block the install — but every secret
added later has to be encrypted to this key, so capture it now.

### 6. Install

```sh
nixos-install --flake /root/nixos-config#rhea --no-root-password
```

### 7. Check the bootloader — before rebooting

```sh
bootctl --esp-path=/mnt/boot status
ls -l /mnt/boot/EFI/systemd/systemd-bootx64.efi \
      /mnt/boot/EFI/BOOT/BOOTX64.EFI     # removable fallback — do not reboot without it
diff -r -x random-seed /mnt/boot /mnt/boot2   # rsync ran; the second ESP is a copy
```

`bootctl` writes a single NVRAM entry, pointing at nvme0's ESP. Add the second
one by hand so the machine still boots from NVRAM if that disk dies:

```sh
efibootmgr -v                                    # find the entry bootctl created
efibootmgr -c -d /dev/nvme1n1 -p 1 \
  -L "Linux Boot Manager (nvme1)" \
  -l '\EFI\systemd\systemd-bootx64.efi'
efibootmgr -v                                    # confirm both, check BootOrder
```

### 8. Reboot

```sh
sync; reboot
```

From the workstation — the rescue, kexec and installed systems all have
different host keys:

```sh
ssh-keygen -R rhea.mhnet.dev
ssh-keygen -R 116.202.233.38
ssh-keygen -R '[rhea.mhnet.dev]:50642'

ssh -p 50642 mh@rhea.mhnet.dev     # compare the fingerprint against step 5
```

## Verifying the install

```sh
systemctl --failed                         # must be empty
journalctl -b -u sysroot-var-log.mount -u sysroot-var-lib-nixos.mount

for m in /nix /bulk /boot /boot2 /var/log /var/lib/nixos; do
  findmnt -no TARGET,SOURCE,FSTYPE "$m" || echo "MISSING: $m"
done
findmnt -t tmpfs /                         # / is tmpfs, size=16G

lvs -a -o+lv_layout,devices vgpool         # lvnix raid1, rimages on different PVs
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPENAME,MOUNTPOINT

bootctl status                             # systemd-boot, ESP = /boot
diff -r -x random-seed /boot /boot2        # identical apart from the seed
efibootmgr -v                              # both entries

echo $HOME                                 # /nix/persist/home/mh
id mh                                      # uid 1000
readlink -f /etc/machine-id                # /nix/persist/etc/machine-id
```

`/boot/loader/random-seed` is deliberately not synced — systemd-boot rewrites it
on every boot, so it differs from `/boot2` as soon as the machine has booted
once. Every `-x random-seed` above is there for that reason; nothing else in the
ESP changes outside a bootloader install.

Then the two tests that actually prove the design:

**Reboot test.** `touch ~/canary`, then `reboot`. Afterwards `~/canary` must
still exist, `journalctl --list-boots` must show more than one boot, and
`/etc/machine-id` must be unchanged. That is what proves the persistence layer
works — a tmpfs root hides these failures otherwise.

**Single-disk boot test.** Needs a KVM session. Confirm the two ESPs are in sync
first (`diff -r -x random-seed /boot /boot2`), then boot with only one NVMe
enabled, once per disk. Both must reach a login prompt — for nvme1 that means
the firmware picks up its own ESP, which is what the second `efibootmgr` entry
and the `\EFI\BOOT\BOOTX64.EFI` fallback are for. Expect, on each run: one of
`/boot` and `/boot2` missing (both are `nofail`, so neither may block the boot),
`/nix` active on its surviving raid1 leg, and `/bulk` gone when its disk is.
Restore the boot order, reboot, and confirm the `lvnix` mirror has resynced
before calling it done.

After replacing a disk, re-run disko for that disk (or `sgdisk`/`mkfs.vfat` by
hand) and then `nixos-rebuild boot` — nothing repopulates the new ESP on its
own. Check for the rsync warning in the output, then
`diff -r -x random-seed /boot /boot2`.

## Secrets

`secrets.nix` is keyed on the host's ssh key from step 5. From the devShell:

```sh
nix develop -c agenix -e <secret>.age
nix develop -c agenix -r                   # rekey after changing recipients
```
