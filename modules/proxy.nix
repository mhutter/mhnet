{
  config,
  lib,
  persist,
  ...
}:
let
  cfg = config.mhnet.proxy;

  # ACME account key and every issued certificate. / is tmpfs, so this has to
  # live on ${persist}: otherwise Caddy re-issues on every boot and runs into
  # Let's Encrypt's duplicate-certificate limit within a week. Under ${persist}
  # it is also covered by mhnet.backup.paths already.
  dataDir = "${persist}/var/lib/caddy";

  mkVHost = host: {
    serverAliases = host.aliases;
    logFormat = lib.mkIf (!host.log) "output discard";
    extraConfig = lib.concatStringsSep "\n" (
      # remote_ip is the peer Caddy sees. That is the real client only because
      # nothing proxies in front of rhea — put a Cloudflare orange cloud or a
      # tunnel there and every allowlist silently matches everyone. The fix
      # would be `trusted_proxies` in globalConfig plus the client_ip matcher.
      lib.optional (host.allowFrom != [ ]) ''
        @denied not remote_ip ${lib.concatStringsSep " " host.allowFrom}
        respond @denied 403
      ''
      ++ lib.optional (host.forwardAuth != null) ''
        forward_auth ${host.forwardAuth.upstream} {
          uri ${host.forwardAuth.uri}
          ${lib.optionalString (
            host.forwardAuth.copyHeaders != [ ]
          ) "copy_headers ${lib.concatStringsSep " " host.forwardAuth.copyHeaders}"}
        }

        # The sign-in flow itself: callback, sign-out, the provider redirect.
        handle ${host.forwardAuth.prefix}/* {
          reverse_proxy ${host.forwardAuth.upstream}
        }
      ''
      ++ [ "reverse_proxy ${host.upstream}" ]
      ++ lib.optional (host.extraConfig != "") host.extraConfig
    );
  };
in
{
  options.mhnet.proxy.hosts = lib.mkOption {
    description = ''
      Virtual hosts served by Caddy. The attribute name is the hostname and the
      certificate's subject at once — see docs/proxy.md.
    '';
    default = { };
    example = lib.literalExpression ''
      {
        "app.mhnet.app".upstream = "127.0.0.1:8080";
        "private.mhnet.app" = {
          upstream = "unix//run/private/http.sock";
          allowFrom = [ "203.0.113.0/24" "2001:db8::/32" ];
        };
      }
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          upstream = lib.mkOption {
            type = lib.types.str;
            example = "127.0.0.1:8080";
            description = ''
              Where to send requests, in Caddy's `reverse_proxy` notation:
              `host:port`, or `unix//run/app/http.sock` for a Unix socket.
            '';
          };

          aliases = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Extra hostnames served by the same vhost. Each one needs its own
              DNS record and ends up on the same certificate.
            '';
          };

          allowFrom = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "203.0.113.0/24" ];
            description = ''
              Client addresses or CIDRs allowed to reach this host. The empty
              list means public. Everything else gets a 403 — including the
              ACME HTTP-01 challenge's own path, which is served by Caddy
              before site routing and is therefore unaffected.
            '';
          };

          forwardAuth = lib.mkOption {
            default = null;
            description = ''
              Delegate authentication to an external auth service, typically
              oauth2-proxy. Nothing runs one yet — this is the hook.
            '';
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  upstream = lib.mkOption {
                    type = lib.types.str;
                    example = "127.0.0.1:4180";
                    description = "The auth service, in `reverse_proxy` notation.";
                  };

                  uri = lib.mkOption {
                    type = lib.types.str;
                    default = "/oauth2/auth";
                    description = "Verification endpoint the auth service answers on.";
                  };

                  copyHeaders = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "X-Auth-Request-User"
                      "X-Auth-Request-Email"
                    ];
                    description = ''
                      Response headers copied onto the request before it is
                      proxied, so the app learns who the user is.
                    '';
                  };

                  prefix = lib.mkOption {
                    type = lib.types.str;
                    default = "/oauth2";
                    description = ''
                      Path prefix proxied to the auth service unauthenticated,
                      for the redirect and callback of the sign-in flow.
                    '';
                  };
                };
              }
            );
          };

          log = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Write an access log to `/var/log/caddy/access-<host>.log`. Caddy
              rolls it itself (100 MiB, 10 files); /var/log is persisted but
              excluded from backups.
            '';
          };

          extraConfig = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra Caddyfile directives for this vhost.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.hosts != { }) {
    # Only the ACME contact address, as ACME_EMAIL=… — Caddy expands {$VAR} when
    # it parses the Caddyfile, so the address stays out of the nix store and out
    # of this public repository. systemd reads EnvironmentFile= as root before
    # dropping to the caddy user, so the secret keeps its 0400 root:root.
    age.secrets.caddy-env.file = ../secrets/caddy-env.age;

    services.caddy = {
      enable = true;
      inherit dataDir;
      environmentFile = config.age.secrets.caddy-env.path;

      # 80 and 443/tcp plus 443/udp for HTTP/3. 80 is not optional: it carries
      # the HTTP-01 challenge and the redirect to HTTPS.
      openFirewall = true;

      globalConfig = ''
        email {$ACME_EMAIL}

        # Prometheus metrics on the admin endpoint, which stays on localhost:2019.
        metrics

        # The module reloads rather than restarts on a config change, and Caddy's
        # default grace period is infinite: one long-lived connection would hang
        # the reload, and with it the activation.
        grace_period 10s
      '';

      virtualHosts = lib.mapAttrs (_: mkVHost) cfg.hosts;
    };

    # dataDir is only created automatically at the default /var/lib/caddy, where
    # the module sets StateDirectory=caddy. ReadWritePaths and the caddy user's
    # home follow dataDir on their own.
    systemd.tmpfiles.settings."10-caddy".${dataDir}.d = {
      mode = "0700";
      user = "caddy";
      group = "caddy";
    };

    # ${persist} is a separate LV; the upstream unit orders itself against
    # /var/lib only.
    systemd.services.caddy.unitConfig.RequiresMountsFor = dataDir;

    # A drop-in over the unit shipped with the caddy package, so the capability
    # lists need an empty entry first: they would otherwise append to it.
    # CAP_NET_ADMIN is in that unit only so quic-go can force its UDP buffer
    # sizes; the sysctls below do the same without handing Caddy the capability.
    systemd.services.caddy.serviceConfig = {
      AmbientCapabilities = [
        ""
        "CAP_NET_BIND_SERVICE"
      ];
      CapabilityBoundingSet = [
        ""
        "CAP_NET_BIND_SERVICE"
      ];

      # dataDir is already in the module's ReadWritePaths, the access logs in
      # its LogsDirectory.
      ProtectSystem = "strict";
      ProtectProc = "invisible";
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectHostname = true;
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      # Go does not JIT.
      MemoryDenyWriteExecute = true;
      SystemCallFilter = [ "@system-service" ];
      SystemCallErrorNumber = "EPERM";
      SystemCallArchitectures = "native";
      RemoveIPC = true;
      DevicePolicy = "closed";
      # No PrivateUsers: CAP_NET_BIND_SERVICE in a user namespace does not
      # reach the host's network namespace, so 80 and 443 would fail to bind.
    };

    # Replaces CAP_NET_ADMIN: without it quic-go cannot raise its own UDP
    # buffers and logs a warning on every start. 7.5 MB is Caddy's documented
    # value.
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 7500000;
      "net.core.wmem_max" = 7500000;
    };

    mhnet.notify.units = [ "caddy.service" ];
  };
}
