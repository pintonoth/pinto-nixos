{ inputs, ... }:

{
  imports = [
    ../common.nix
    ../../modules/desktop/umbriel.nix
    ../../modules/desktop/xdg-portal.nix
  ];

  home-manager.sharedModules = [ inputs.umbriel.homeModules.default ];
  home-manager.users.jensend = import ../../home/umbriel.nix;
}
