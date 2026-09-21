{
  persist,
  username,
  ...
}:
{
  # services.openssh.openFirewall defaults to true and already opens
  # services.openssh.ports, so no networking.firewall entry is needed here.
  services.openssh = {
    enable = true;
    ports = [ 50642 ];
    allowSFTP = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ username ];
    };
    hostKeys = [
      {
        path = "${persist}/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
}
