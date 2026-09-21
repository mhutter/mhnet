{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  ## Don't install documentation
  documentation = {
    enable = false;
    man.enable = false;
    info.enable = false;
    doc.enable = false;
  };

  # Don't include default packages (at the time of writing: perl, rsync, strace)
  # See: https://search.nixos.org/options?channel=26.05&show=environment.defaultPackages
  environment.defaultPackages = lib.mkForce [ ];
  environment.systemPackages = with pkgs; [
    btop
    fd
    rsync
    tmux
  ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
