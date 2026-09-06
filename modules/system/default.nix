{ pkgs, ... }:
{
  imports = [
    ./boot.nix
    ./users.nix
    ./locale.nix
    ./network.nix
    ./packages.nix
    ./drives.nix
    ./audio.nix
  ];

  fonts.packages = with pkgs; [
    inter
    noto-fonts
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "JetBrainsMono Nerd Font" ];
    serif = [ "JetBrainsMono Nerd Font" ];
    monospace = [ "JetBrainsMono Nerd Font" ];
    emoji = [ "Noto Color Emoji" ];
  };

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
      package = pkgs.colloid-icon-theme;
      light = "Colloid-Light";
      dark = "Colloid-Dark";
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
