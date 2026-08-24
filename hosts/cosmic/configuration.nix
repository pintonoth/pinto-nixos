{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../hosts/common.nix
    ../../modules/desktop/cosmic.nix
  ];

  home-manager.users.jensend = import ../../home/desktop-common.nix;
}
