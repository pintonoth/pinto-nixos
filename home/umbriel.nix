{ ... }:

{
  imports = [
    ./noctalia.nix
  ];

  programs.umbriel = {
    enable = true;
    settings = ./config/umbriel/config.toml;
  };

  xdg.configFile = {
    "umbriel/keybinds.toml".source = ./config/umbriel/keybinds.toml;
    "umbriel/outputs.toml".source = ./config/umbriel/outputs.toml;
    "umbriel/windowrules.toml".source = ./config/umbriel/windowrules.toml;
    "umbriel/appearance.toml".source = ./config/umbriel/appearance.toml;
    "umbriel/animation.toml".source = ./config/umbriel/animation.toml;
    "umbriel/layout.toml".source = ./config/umbriel/layout.toml;
  };
}
