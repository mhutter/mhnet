host := "rhea"
port := "50642"
remote_dir := "/nix/persist/home/mh/nixos-config"

# List available recipes
default:
    @just --list

## NixOS — rhea

# The working tree carries untracked secrets that must not reach the host:
# .env holds the B2 *master* key, .vaultpass the Ansible vault password.
# ansible/ is no part of the flake, so it is left behind too.

# Copy this repo to the host — uncommitted changes included, .git excluded
sync:
    rsync -a --delete -e 'ssh -p {{ port }}' \
      --exclude .git --exclude .direnv --exclude .ansible \
      --exclude .env --exclude .vaultpass \
      --exclude /ansible --exclude /hosts.xml \
      {{ justfile_directory() }}/ {{ host }}:{{ remote_dir }}/

# Build and activate, and make it the boot default
switch: (rebuild "switch")

# Build and make it the boot default, without activating now
boot: (rebuild "boot")

# Activate without touching the bootloader — a reboot reverts it
test: (rebuild "test")

# Evaluate and build only, no activation
dry: (rebuild "dry-build")

# Build only, no activation
build: (rebuild "build")

# Everything runs on the host: `nixos-rebuild --build-host/--target-host` would
# evaluate the flake locally and only copy the derivations over.
[private]
rebuild op: sync
    ssh -t -p {{ port }} {{ host }} 'sudo nixos-rebuild -L {{ op }} --flake {{ remote_dir }}#rhea --option abort-on-warn true --show-trace'

## Ansible

# Run the Bootstrap playbook with the minimum set of tasks
bootstrap:
    ansible-playbook ansible/playbooks/bootstrap.yml --tags bootstrap
