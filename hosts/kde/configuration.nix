{ ... }:

{
  imports = [
    ../common.nix
    ../../modules/desktop/kde.nix
  ];

  home-manager.users.jensend = import ../../home/kde.nix;
}
