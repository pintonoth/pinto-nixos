{
  config,
  inputs,
  pkgs,
  ...
}:
let
  persona = import ./package.nix { inherit pkgs inputs; };
in
{
  imports = [
    ../../configuration.nix
    ../../modules/desktop/xdg-portal.nix
    inputs.noctalia-greeter.nixosModules.default
  ];

  home-manager.users.jensend = import ./home.nix;
  programs.hyprland.enable = true;
  services.displayManager.defaultSession = "hyprland";
  xdg.portal.config.Hyprland = {
    default = [
      "hyprland"
      "gtk"
    ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
  };

  programs.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "hyprland";
      appearance = {
        scheme = "Catppuccin";
        theme_mode = "dark";
      };
      cursor = {
        theme = config.stylix.cursor.name;
        size = config.stylix.cursor.size;
        path = "${config.stylix.cursor.package}/share/icons";
      };
      idle.timeout = 300;
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  # Persona's information panels use these services directly.
  hardware.bluetooth.enable = true;
  services.upower.enable = true;

  fonts.packages = [
    persona.fonts
    pkgs.libertine
    pkgs.material-symbols
    pkgs.noto-fonts-cjk-sans
  ];
}
