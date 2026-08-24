{ pkgs, ... }:

{
  imports = [
    ./desktop-common.nix
  ];

  programs.umbriel = {
    enable = true;
    settings = ./config/umbriel/config.toml;
  };

  xdg.configFile = {
    "umbriel/keybinds.toml".source = ./config/umbriel/keybinds.toml;
    "umbriel/outputs.toml".source = ./config/umbriel/outputs.toml;
    "umbriel/windowrules.toml".source = ./config/umbriel/windowrules.toml;
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
  };

  home.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };

  gtk = {
    enable = true;

    theme = {
      name = "catppuccin-mocha-mauve-standard";
      package = pkgs.catppuccin-gtk.override {
        accents = [ "mauve" ];
        variant = "mocha";
      };
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
