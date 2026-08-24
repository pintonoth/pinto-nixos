{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../hosts/common.nix
    ../../modules/desktop/kineticwe.nix
  ];

  home-manager.users.jensend = import ../../home/desktop-common.nix;
}
