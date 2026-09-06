{ lib, ... }:

{
  imports = [
    ../../configuration.nix
    ../../modules/desktop/noctalia.nix
    ../../modules/desktop/xdg-portal.nix
  ];

  home-manager.users.jensend = import ./home.nix;
  services.displayManager.defaultSession = lib.mkForce "niri";

  programs.niri.enable = true;

  programs.noctalia-greeter.settings = {
    session.default = "niri";

    appearance = {
      scheme = "Catppuccin";
      theme_mode = "dark";
      corner_radius_scale = 1.0;
    };
  };
}
