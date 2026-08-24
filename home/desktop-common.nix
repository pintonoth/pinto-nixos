{ ... }:

{
  imports = [
    ./kitty.nix
  ];

  home.username = "jensend";
  home.homeDirectory = "/home/jensend";

  home.stateVersion = "26.05";
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "inode/directory" = [ "Thunar.desktop" ];
      "x-scheme-handler/heroic" = [
        "com.heroicgameslauncher.hgl.desktop"
      ];

      "x-scheme-handler/mailto" = [
        "chromium-browser.desktop"
      ];

      "x-scheme-handler/lmstudio" = [
        "lm-studio.desktop"
      ];
      "application/pdf" = [ "org.pwmt.zathura.desktop" ];

      "image/png" = [ "imv.desktop" ];
      "image/jpeg" = [ "imv.desktop" ];

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
