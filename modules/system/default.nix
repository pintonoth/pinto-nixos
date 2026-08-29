{ pkgs, ... }:
{
  imports = [
    ./locale.nix
    ./network.nix
    ./packages.nix
    ./drives.nix
    ./audio.nix
  ];

  stylix = {
    enable = true;
    autoEnable = false;
    polarity = "dark";

    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };

    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme;
      light = "Papirus-Light";
      dark = "Papirus-Dark";
    };

    fonts = {
      sansSerif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };

      sizes.applications = 10;
    };
  };
}
