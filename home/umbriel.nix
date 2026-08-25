{ ... }:

{
  programs.umbriel = {
    enable = true;
    settings = ./config/umbriel/config.toml;
  };

  xdg.configFile = {
    "umbriel/keybinds.toml".source = ./config/umbriel/keybinds.toml;
    "umbriel/outputs.toml".source = ./config/umbriel/outputs.toml;
    "umbriel/windowrules.toml".source = ./config/umbriel/windowrules.toml;
  };
}
