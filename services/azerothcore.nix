{ config, lib, ... }:
let
  xpRate = 3;
in
{
  age.secrets.azerothcoreTotp.file = ../secrets/azerothcore-totp.age;

  services.azerothcore = {
    enable = true;
    clientData.enable = true;
    totpMasterSecretFile = config.age.secrets.azerothcoreTotp.path;

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

      ### Own settings
      "Rate.Reputation.Gain" = 3;
      "Rate.Honor" = 3;
      "Rate.XP.Kill" = xpRate;
      "Rate.XP.Quest" = xpRate;
      "Rate.XP.Quest.DF" = xpRate;
      "Rate.XP.Explore" = xpRate;
      "Rate.XP.Pet" = xpRate;
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
  };
}
