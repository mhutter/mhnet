{ username, ... }:
{
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ username ];
    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    download-buffer-size = 1024 * 1024 * 1024; # 1 GiB, up from 64 MiB
    # Keep the build inputs of live paths (keep-derivations is on by default),
    # so GC doesn't drop sources of locally built packages (Docspell,
    # AzerothCore) and every weekly rebuild re-downloads them from GitHub.
    keep-outputs = true;
  };
}
