{ config, pkgs, ... }:
let
  ftModel = builtins.fetchurl {
    url = "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin";
    sha256 = "0kkncb1swi2azh0ci7kq0sfg1mw559wy8jafhk3iq9mwa5afqsby";
  };

  mkNgrams =
    lang: version: hash:
    pkgs.fetchzip {
      inherit hash version;
      pname = "languagetool-ngram-data-${lang}";
      url = "https://languagetool.org/download/ngram-data/ngrams-${lang}-${version}.zip";
    };

  # See https://dev.languagetool.org/finding-errors-using-n-gram-data
  ngramData = pkgs.linkFarm "languagetool-ngram-data" {
    de = mkNgrams "de" "20150819" "sha256-b+dPqDhXZQpVOGwDJOO4bFTQ15hhOSG6WPCx8RApfNg=";
    en = mkNgrams "en" "20150817" "sha256-v3Ym6CBJftQCY5FuY6s5ziFvHKAyYD3fTHr99i6N8sE=";
  };

in
{
  mhnet.proxy.hosts."lt.mhnet.app".upstream =
    "127.0.0.1:${toString config.services.languagetool.port}";
  mhnet.notify.units = [ "languagetool.service" ];

  services.languagetool = {
    enable = true;
    # nixpkgs' jlinked JRE lacks java.management, which PipelinePool needs
    # for its JMX MBeans once pipelineCaching is on. The module runs
    # `package.jre`, so swapping the passthru is enough.
    package = pkgs.languagetool.overrideAttrs (old: {
      passthru = old.passthru // {
        jre = pkgs.jre_minimal.override {
          modules = [
            "java.base"
            "java.datatransfer"
            "java.desktop"
            "java.management"
            "java.naming"
            "java.sql"
            "java.xml"
            "jdk.httpserver"
          ];
        };
      };
    });
    allowOrigin = "'*'";
    settings = {
      premiumAlways = true;
      # Use fasttext for language detection
      fasttextBinary = "${pkgs.fasttext}/bin/fasttext";
      fasttextModel = ftModel;
      # Improve caching
      pipelineCaching = true;
      maxPipelinePoolSize = 500;
      pipelineExpireTimeInSeconds = 3600;
      # Enable n-gram word confusion detection
      languageModel = ngramData;
    };
    jvmOptions = [ "-Xmx2g" ];
  };
}
