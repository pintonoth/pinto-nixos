{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../hosts/common.nix
    ../../modules/desktop/noctalia.nix
  ];

  home-manager.users.jensend = import ../../home/niri.nix;
  services.displayManager.defaultSession = lib.mkForce "niri";
}
