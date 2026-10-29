{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mhnet.notify;
  host = config.networking.hostName;

  # Telegram, not ntfy.sh: anonymous ntfy.sh quota is per IP, a free account
  # does not change that, and rhea's IPv6 bucket is shared with neighbours
  # who exhaust it daily.
  telegram = config.age.secrets.telegram-env.path;
  healthchecks = config.age.secrets.healthchecks-url.path;

  tools = [
    pkgs.curl
    config.systemd.package
  ];

  # A oneshot template instantiated per unit: `on<Event> = [ "<name>@%n.service" ]`
  # and systemd expands %n to the triggering unit's full name, which arrives
  # here as the instance, %i.
  mkPush =
    {
      event,
      lines,
      icon,
      silent,
    }:
    {
      description = "Push a notification that %i ${event}";
      # Deliberately no wantedBy: only ever started by an On<Event>=.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = tools;
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = telegram;
      };
      scriptArgs = "%i";
      script = ''
        unit="$1"

        # Telegram caps a message at 4096 characters. A byte cut can split a
        # line, and a multi-byte character with it, so drop the partial line.
        body="$(journalctl --unit "$unit" --lines ${toString lines} --no-pager --output cat 2>/dev/null)"
        if [ "''${#body}" -gt 2500 ]; then
          body="$(printf '%s' "$body" | tail -c 2500 | tail -n +2)"
        fi
        [ -n "$body" ] || body="(no journal output)"
        body="$(printf '%s' "$body" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"

        # The token is part of the URL, so it goes in through a file
        # descriptor rather than the process list. Text over stdin.
        if ! out="$(
          printf '${icon} <b>%s: %s ${event}</b>\n<pre>%s</pre>' "${host}" "$unit" "$body" |
            curl --fail-with-body --silent --show-error --max-time 20 --retry 3 \
              --config <(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN") \
              --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
              --data-urlencode "parse_mode=HTML" \
              --data-urlencode "disable_notification=${lib.boolToString silent}" \
              --data-urlencode "text@-"
        )"; then
          printf '%s\n' "$out" >&2
          exit 1
        fi
      '';
    };

  wire =
    event: template: units:
    lib.listToAttrs (
      map (
        unit:
        lib.nameValuePair (lib.removeSuffix ".service" unit) {
          ${event} = [ "${template}@%n.service" ];
        }
      ) units
    );
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

    successUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nixos-upgrade.service" ];
      description = ''
        Units that get a low-priority `OnSuccess=` push. Meant for rare,
        consequential jobs — not for anything that runs more than daily.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:3/5"; # every 5 minutes, offset by 3 minutes.
      description = ''
        How often the heartbeat pings Healthchecks. The check's period and grace
        live in the Healthchecks UI, not here — this only has to ping more often
        than the period.
      '';
    };
  };

  config = {
    age.secrets = {
      telegram-env.file = ../secrets/telegram-env.age;
      healthchecks-url.file = ../secrets/healthchecks-url.age;
    };

    systemd.services = {
      ## Failure pushes — Telegram tells you *what* broke
      "notify-failure@" = mkPush {
        event = "failed";
        lines = 30;
        icon = "🚨";
        silent = false;
      };

      ## Success pushes — a quiet receipt, e.g. "the upgrade ran"
      # A handful of lines is enough to see whether a reboot was scheduled.
      "notify-success@" = mkPush {
        event = "succeeded";
        lines = 5;
        icon = "✅";
        silent = true;
      };

      ## Heartbeat — Healthchecks tells you *that* nothing broke
      # The one alert Telegram structurally cannot raise: if an upgrade reboots
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
    # recursiveUpdate, not //: a unit may sit in both lists.
    // lib.recursiveUpdate (wire "onFailure" "notify-failure" cfg.units) (
      wire "onSuccess" "notify-success" cfg.successUnits
    );

    # Spread the pings off the top of the hour; Healthchecks' grace absorbs it.
    systemd.timers.healthchecks-ping.timerConfig.RandomizedDelaySec = "25";
  };
}
