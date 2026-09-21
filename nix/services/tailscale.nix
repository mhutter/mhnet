{ persist, ... }:
{
  services.tailscale = {
    enable = true;
    ## UDP port 41641
    openFirewall = true;
  };

  # tailscaled keeps its node key and machine identity in
  # /var/lib/tailscale/tailscaled.state (StateDirectory=tailscale in the
  # upstream systemd unit).
  environment.persistence.${persist}.directories = [
    {
      directory = "/var/lib/tailscale";
      user = "root";
      group = "root";
      mode = "0700"; # matches StateDirectoryMode=0700
    }
  ];
}
