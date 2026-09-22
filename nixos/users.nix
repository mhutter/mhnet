{
  username,
  sshPublicKeys,
  persist,
  ...
}:
{
  users = {
    mutableUsers = false;
    users = {
      root.hashedPassword = "!"; # Disable root login
      "${username}" = {
        isNormalUser = true;
        # Pinned so ownership under ${persist} stays correct even if the
        # uid/gid map in /var/lib/nixos is ever lost.
        uid = 1000;
        # / is tmpfs, so $HOME has to live on /nix to survive a reboot.
        # isNormalUser already implies createHome = true.
        home = "${persist}/home/${username}";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = sshPublicKeys;
      };
    };
    groups.${username}.gid = 1000;
  };

  security.sudo.enable = false;
  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };
}
