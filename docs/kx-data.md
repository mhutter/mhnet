# kx-data

`services/kx-data.nix` runs the app on `kx-data.mhnet.app`. The NixOS side
(unit, secret, proxy host, failure push) follows the normal `main` /
`just switch` flow. The binary does not: it lives in its own profile,
`/nix/var/nix/profiles/kx-data`, so a deploy is a build plus a restart, not a
system rebuild, and `system.autoUpgrade` never touches it.

Until the first deploy the unit is skipped (`ConditionPathExists`), not failed.

## Data

`${persist}/var/lib/kx-data`, passed as `KX_DATA_DIR`, owned by the static
`kx-data` user. Covered by `mhnet.backup` through `${persist}`. A profile
rollback does not roll this back.

## Secret

`secrets/kx-data-env.age` is an environment file:

```sh
agenix -e secrets/kx-data-env.age
```

```sh
KX_OWNER_HASH='...'
```

Single quotes keep systemd from touching `$` in the hash.

## Deploy

Built on rhea, from a pushed commit of the app's flake:

```sh
ssh rhea "sudo nix build github:<owner>/<repo>/<rev> \
  --profile /nix/var/nix/profiles/kx-data \
  && sudo systemctl restart kx-data"
```

## Rollback

```sh
ssh rhea "sudo nix-env -p /nix/var/nix/profiles/kx-data --rollback \
  && sudo systemctl restart kx-data"
```

`nix-env -p /nix/var/nix/profiles/kx-data --list-generations` lists what is
there. Generations older than 90 days go with the weekly `nix.gc` run.
