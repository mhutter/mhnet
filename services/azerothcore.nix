{
  config,
  lib,
  persist,
  pkgs,
  azerothcoreModules,
  ...
}:
let
  # Manual, on-demand snapshots (e.g. before a module or schema change), kept
  # outside the nightly dump dir, which every backup run empties. Still under
  # ${persist}, so restic picks them up too.
  snapshotDir = "${persist}/var/backups/mysql-snapshots";

  snapshot-acore-dbs = pkgs.writeShellApplication {
    name = "snapshot-acore-dbs";
    runtimeInputs = [
      config.services.mysql.package
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.util-linux
    ];
    text = ''
      [ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

      out="${snapshotDir}/acore-$(date +%Y-%m-%d-%H-%M).tgz"
      [ -e "$out" ] && { echo "$out exists" >&2; exit 1; }

      # Staged on disk next to the archive, not in /tmp: / is tmpfs.
      tmp=$(mktemp -d "${snapshotDir}/.tmp.XXXXXX")
      trap 'rm -rf "$tmp" "$out.partial"' EXIT

      # Same flags as the nightly hook in services/mysql.nix: consistent
      # InnoDB snapshot without stopping the worldserver.
      runuser -u mysql -- mysql --user=mysql --batch --skip-column-names \
        --execute "SHOW DATABASES LIKE 'acore\_%'" \
        | while read -r db; do
            echo "dumping $db"
            runuser -u mysql -- mysqldump --user=mysql \
              --single-transaction --routines --events --triggers \
              --databases "$db" \
              > "$tmp/$db.sql"
          done
      [ -n "$(ls -A "$tmp")" ] || { echo "no acore_* databases" >&2; exit 1; }

      # .partial until done: an aborted run leaves no valid-looking archive.
      tar -czf "$out.partial" -C "$tmp" .
      mv "$out.partial" "$out"
      echo "$out"
    '';
  };
in
{
  age.secrets.azerothcoreTotp.file = ../secrets/azerothcore-totp.age;

  environment.systemPackages = [ snapshot-acore-dbs ];

  systemd.tmpfiles.settings."10-mysql-snapshots".${snapshotDir}.d = {
    mode = "0700";
    user = "root";
    group = "root";
  };

  services.azerothcore = {
    enable = true;
    clientData.enable = true;
    totpMasterSecretFile = config.age.secrets.azerothcoreTotp.path;

    extraModules = azerothcoreModules;

    # https://github.com/mod-playerbots/azerothcore-wotlk/blob/Playerbot/src/server/apps/worldserver/worldserver.conf.dist
    worldserver.settings = {
      ## Recommendations from
      ## https://github.com/mod-playerbots/mod-playerbots/wiki/Playerbot-Configuration,
      ## commented out values are equal to their defaults

      ## bots might not pickup quests in certain condidations
      "Quests.IgnoreAutoAccept" = 1;

      ## Performance
      # "PreloadAllNonInstancedMapGrids" = 0;
      # "SetAllCreaturesWithWaypointMovementActive" = 0; # does not exist in worldserver.conf.dist?
      # "DontCacheRandomMovementPaths" = 0;
      "MapUpdate.Threads" = lib.mkForce 6; # wiki: cores - 2, never more than 8
      # "MapUpdateInterval" = 10;
      # "MinWorldUpdateTime" = 1;

      ## no player limit for the bots
      "PlayerLimit" = 0;

      ## prevent buggy situations
      ## Should the player leave their group when they log out?
      ## (It does not affect raids or dungeon finder groups)
      "LeaveGroupOnLogout.Enabled" = 1;

      ## Required by mod-individual-progression. It also sets both itself at
      ## runtime (IndividualProgression.SimpleConfigOverride), but that is
      ## easy to switch off without noticing progress is no longer saved.
      "EnablePlayerSettings" = 1;
      "DBC.EnforceItemAttributes" = 0;

      ### Own settings
      "Rate.Reputation.Gain" = 2;
      "Rate.Honor" = 2;
      "Rate.XP.Kill" = 2;
      "Rate.XP.Quest" = 2;
      "Rate.XP.Quest.DF" = 2;
      "Rate.XP.Explore" = 2;
      "Rate.XP.Pet" = 2;

    };

    # https://github.com/mod-playerbots/mod-playerbots/blob/master/conf/playerbots.conf.dist
    moduleSettings."playerbots.conf" = {
      "AiPlayerbot.MinRandomBots" = 512;
      "AiPlayerbot.MaxRandomBots" = 2048;
      # Disable randombots when no real players are logged in
      "AiPlayerbot.DisabledWithoutRealPlayer" = 1;

      ## Recommendations from
      ## https://github.com/mod-playerbots/mod-playerbots/wiki/Playerbot-Configuration,
      ## commented out values are equal to their defaults
      # "AiPlayerbot.BotActiveAlone" = 10;
      # "AiPlayerbot.BotActiveAloneDurationSeconds" = 30; # default
      # "AiPlayerbot.botActiveAloneSmartScale" = 1;
      # "AiPlayerbot.botActiveAloneSmartScaleWhenMinLevel" = 1;
      # "AiPlayerbot.botActiveAloneSmartScaleWhenMaxLevel" = 80;

    };

    # https://github.com/ZhengPeiRu21/mod-individual-progression/blob/master/conf/individualProgression.conf.dist
    ## Upstream defaults for now. BotAccountsRegex "^RNDBOT.*" targets the
    ## playerbots' "rndbot" prefix: AC stores account names uppercased.
    moduleSettings."individualProgression.conf" = {
      ## Suggested Settings
      "IndividualProgression.VanillaPowerAdjustment" = 0.6;
      "IndividualProgression.VanillaHealingAdjustment" = 0.5;
      "IndividualProgression.TBCPowerAdjustment" = 0.6;
      "IndividualProgression.TBCHealingAdjustment" = 0.5;

      ## Early allow content that would be obsolete by the time it is unlocked
      "IndividualProgression.AllowEarlyDungeonSet2" = 1;

      ## TODO: research what exactly this does
      # "IndividualProgression.AllowEarlyScourgeBosses" = 1;
    };
  };
}
