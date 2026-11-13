{ config, pkgs, ... }:
let
  cfg = config.services.nix-serve;
in
{

  age.secrets.nixServeSecretKey.file = ../secrets/nix-serve-secret-key.age;
  mhnet.proxy.hosts."cache.mhnet.app".upstream = "127.0.0.1:${toString cfg.port}";
  services.nix-serve = {
    enable = true;
    bindAddress = "127.0.0.1";
    secretKeyFile = config.age.secrets.nixServeSecretKey.path;
    # upstream hardcodes "Priority: 30" in nix-serve.psgi, no option to configure it
    package = pkgs.nix-serve.overrideAttrs (old: {
      postPatch = ''
        ${old.postPatch or ""}
        substituteInPlace nix-serve.psgi --replace-fail 'Priority: 30' 'Priority: 50'
      '';
    });
  };

  ## Hardening
  # Upstream runs it with DynamicUser and the key via LoadCredential, nothing
  # more. All store access goes through the nix-daemon socket (NIX_REMOTE=daemon)
  # plus plain reads of /nix/store, so the read-only view below suffices. The
  # daemon sees the real uid via SO_PEERCRED, so PrivateUsers does not affect
  # its allowed-users check.
  systemd.services.nix-serve.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateUsers = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectControlGroups = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    # The daemon socket, plus the TCP listener. AF_INET6 only because Perl's
    # address resolution may probe it even for a v4 bind address.
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    # Only Caddy on loopback talks to it.
    IPAddressDeny = "any";
    IPAddressAllow = "localhost";
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    LockPersonality = true;
    RemoveIPC = true;
    # Perl and the nix client have no JIT.
    MemoryDenyWriteExecute = true;
    # An empty list would render no line at all and leave the default set.
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
    ];
    SystemCallErrorNumber = "EPERM";
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
}
