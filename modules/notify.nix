{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mhnet.notify;
  host = config.networking.hostName;

  ntfy = config.age.secrets.ntfy-url.path;
  healthchecks = config.age.secrets.healthchecks-url.path;

  tools = [
    pkgs.curl
    config.systemd.package
  ];
in
{
  options.mhnet.notify = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "restic-backups-rhea.service" ];
      description = ''
        Units that get an `OnFailure=` push. Service modules append their own —
        see docs/updates.md. Names carry the `.service` suffix, because that is
        what systemd's `%n` expands to.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = ''
        How often the heartbeat pings Healthchecks. The check's period and grace
        live in the Healthchecks UI, not here — this only has to ping more often
        than the period.
      '';
    };
  };

  config = {
    age.secrets = {
      ntfy-url.file = ../secrets/ntfy-url.age;
      healthchecks-url.file = ../secrets/healthchecks-url.age;
    };

    systemd.services =
      {
        ## Failure pushes — ntfy tells you *what* broke
        # Instantiated per failing unit: a unit sets
        # `onFailure = [ "notify-failure@%n.service" ]` and systemd expands %n
        # to its own full name, which arrives here as the instance, %i.
        "notify-failure@" = {
          description = "Push a failure notification for %i";
          # Deliberately no wantedBy: only ever started by an OnFailure=.
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = tools;
          serviceConfig.Type = "oneshot";
          scriptArgs = "%i";
          script = ''
            unit="$1"

            # ntfy.sh caps a message at 4 KiB; leave room for the headers.
            body="$(journalctl --unit "$unit" --lines 30 --no-pager --output cat 2>/dev/null | tail -c 2500)"
            [ -n "$body" ] || body="(no journal output)"

            # Body over stdin: --data-binary "$body" would read a journal line
            # that happens to start with @ as a file name.
            printf '%s' "$body" | curl --fail --silent --show-error --max-time 20 --retry 3 \
              --header "Title: ${host}: $unit failed" \
              --header "Priority: high" \
              --header "Tags: rotating_light" \
              --data-binary @- \
              "$(cat ${ntfy})" >/dev/null
          '';
        };

        ## Heartbeat — Healthchecks tells you *that* nothing broke
        # The one alert ntfy structurally cannot raise: if an upgrade reboots
        # and the host never comes back, there is no failing unit left to push
        # anything. A missing ping is the signal, which is also why this must
        # not appear in mhnet.notify.units — its own failure is already covered
        # by the silence it causes.
        healthchecks-ping = {
          description = "Ping Healthchecks so that silence means ${host} is gone";
          startAt = cfg.interval;
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = tools;
          serviceConfig.Type = "oneshot";
          script = ''
            # %/ so that a URL saved with a trailing slash does not become //fail.
            url="$(cat ${healthchecks})"
            url="''${url%/}"

            # is-system-running exits non-zero for every state but "running".
            state="$(systemctl is-system-running || true)"
            case "$state" in
              running | starting)
                endpoint="$url"
                body="$state"
                ;;
              *)
                # degraded and friends: name the failed units, so the alert is
                # actionable even for something nobody wired into
                # mhnet.notify.units.
                endpoint="$url/fail"
                body="$state: $(systemctl list-units --state=failed --no-legend --plain 2>/dev/null || true)"
                ;;
            esac

            printf '%s' "$body" | curl --fail --silent --show-error --max-time 20 --retry 3 \
              --data-binary @- "$endpoint" >/dev/null
          '';
        };
      }
      // lib.listToAttrs (
        map (
          unit:
          lib.nameValuePair (lib.removeSuffix ".service" unit) {
            onFailure = [ "notify-failure@%n.service" ];
          }
        ) cfg.units
      );

    # Spread the pings off the top of the hour; Healthchecks' grace absorbs it.
    systemd.timers.healthchecks-ping.timerConfig.RandomizedDelaySec = "5min";
  };
}
