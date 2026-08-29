{ ... }:

{
  imports = [
    ./kitty.nix
  ];

  home.username = "jensend";
  home.homeDirectory = "/home/jensend";

  programs.bash = {
    enable = true;
    initExtra = ''
      fastfetch --config examples/17.jsonc
    '';
    shellAliases.fm = "yazi";
  };

  home.stateVersion = "26.05";

  stylix.targets.gtk.enable = true;

  # Stylix does not set the desktop-wide libadwaita color-scheme preference.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # Used by Thunar's "Open Terminal Here" action through exo-open.
  xdg.configFile."xfce4/helpers.rc".text = ''
    TerminalEmulator=kitty
  '';

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "inode/directory" = [ "Thunar.desktop" ];
      "text/html" = [ "zen.desktop" ];
      "x-scheme-handler/heroic" = [
        "com.heroicgameslauncher.hgl.desktop"
      ];

      "x-scheme-handler/http" = [ "zen.desktop" ];
      "x-scheme-handler/https" = [ "zen.desktop" ];
      "x-scheme-handler/mailto" = [
        "zen.desktop"
      ];

      "x-scheme-handler/lmstudio" = [
        "lm-studio.desktop"
      ];

      "x-scheme-handler/nordvpn" = [
        "nordvpn.desktop"
      ];

      "video/mp4" = [ "mpv.desktop" ];
    };
    associations.added = {
      "x-scheme-handler/heroic" = [
        "com.heroicgameslauncher.hgl.desktop"
        "heroic.desktop"
      ];

      "x-scheme-handler/lmstudio" = [
        "lm-studio.desktop"
        "LM-Studio.desktop"
      ];
    };

  };
}
