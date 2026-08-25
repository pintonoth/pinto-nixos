{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ./kitty.nix
  ];

  home.username = "jensend";
  home.homeDirectory = "/home/jensend";

  home.packages = with pkgs; [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    btop
    discord
    equibop
    fastfetch
    ffmpeg
    gpu-screen-recorder-gtk
    heroic
    kitty
    lmstudio
    mpv
    nil
    nixd
    obsidian
    pika-backup
    playerctl
    protonup-qt
    qbittorrent
    spotify
    vlc
    whatsapp-electron
    zed-editor
  ];

  programs.bash = {
    enable = true;
    initExtra = ''
      fastfetch --config examples/17.jsonc
    '';
    shellAliases.fm = "yazi";
  };

  home.stateVersion = "26.05";

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

  services.flatpak = {
    enable = true;

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
      {
        name = "mixtapes";
        location = "https://m-obeid.github.io/Mixtapes/mixtapes.flatpakrepo";
      }
    ];

    packages = [
      {
        appId = "com.pocoguy.Muse";
        origin = "mixtapes";
      }
    ];
  };

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
