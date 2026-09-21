{ ... }:
let
  interface = "enp35s0";
in
{
  networking = {
    hostName = "rhea";
    domain = "mhnet.dev";
    useDHCP = false;

    interfaces.${interface} = {
      ipv4.addresses = [
        {
          address = "116.202.233.38";
          prefixLength = 26;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a01:4f8:241:4c27::1";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = "116.202.233.1";
    defaultGateway6 = {
      inherit interface;
      address = "fe80::1";
    };

    ## Hetzner DNS servers
    nameservers = [
      "185.12.64.1"
      "185.12.64.2"
      "2a01:4ff:ff00::add:1"
      "2a01:4ff:ff00::add:2"
    ];
    ## Hetzner NTP servers
    timeServers = [
      "ntp1.hetzner.de"
      "ntp2.hetzner.com"
      "ntp3.hetzner.net"
    ];
  };
}
