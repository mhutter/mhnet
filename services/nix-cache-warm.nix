{ config, pkgs, ... }:
let
  name = "nix-cache-warm";
  flake = "https://github.com/mhutter/nix";

  # Under /nix, so the roots survive the tmpfs root. A symlink directly in
  # gcroots/ is a root on its own, no indirection via gcroots/auto needed.
  rootsDir = "/nix/var/nix/gcroots/${name}";
in
{
  ## Pre-build the workstations, so nix-serve has their updates ready
  # Builds every nixosConfiguration of the flake against freshly updated
  # inputs, i.e. what the next `nix flake update && nixos-rebuild` on those
  # hosts will ask for. The gcroot per host keeps the closure alive between
  # runs and across nix-gc; each run replaces it, releasing the previous one.
  systemd.services.${name} = {
    description = "Build the nixosConfigurations of ${flake} to warm the cache";
    startAt = "*-*-* 05:00:00";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      config.nix.package
      pkgs.git
    ];

    environment.HOME = "%C/${name}";

    serviceConfig = {
      Type = "oneshot";
      User = name;
      Group = name;
      # Fetcher and eval caches live in $HOME; losing them on reboot is fine.
      CacheDirectory = name;
      RuntimeDirectory = name;
      # The builds themselves run in nix-daemon, so this only covers
      # evaluation and the checkout.
      ProtectSystem = "strict";
      ReadWritePaths = [ rootsDir ];
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
    };

    script = ''
      src="$RUNTIME_DIRECTORY/src"
      git clone --quiet --depth 1 ${flake} "$src"
      cp "$src/secrets.fake.nix" "$src/secrets.nix"
      nix flake update --flake "$src"

      hosts="$(nix eval --raw "$src#nixosConfigurations" \
        --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)')"

      # One broken host must not keep the others cold; fail at the end instead.
      failed=""
      for host in $hosts; do
        nix build --print-build-logs \
          --out-link "${rootsDir}/$host" \
          "$src#nixosConfigurations.$host.config.system.build.toplevel" \
          || failed="$failed $host"
      done

      # Hosts dropped from the flake would otherwise stay pinned forever.
      for link in ${rootsDir}/*; do
        [ -L "$link" ] || continue
        grep -qxF "$(basename "$link")" <<<"$hosts" || rm "$link"
      done

      if [ -n "$failed" ]; then
        echo "failed to build:$failed" >&2
        exit 1
      fi
    '';
  };

  # Catch up on a run missed while the host was down.
  systemd.timers.${name}.timerConfig.Persistent = true;

  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };
  users.groups.${name} = { };

  systemd.tmpfiles.settings.${name}.${rootsDir}.d = {
    mode = "0755";
    user = name;
    group = name;
  };

  mhnet.notify.units = [ "${name}.service" ];
}
