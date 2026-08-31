{ pkgs, ... }:

{
  imports = [
    ./kitty.nix
  ];

  home.username = "jensend";
  home.homeDirectory = "/home/jensend";
  home.stateVersion = "26.05";
  home.packages = with pkgs; [
    adw-gtk3
    glib
  ];

  home.sessionVariables.GSETTINGS_SCHEMA_DIR =
    pkgs.glib.getSchemaPath pkgs.gsettings-desktop-schemas;

  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      fastfetch --config examples/17.jsonc
    '';
  };

  stylix.targets.gtk.enable = false;
  gtk.enable = true;

  # Stylix does not set the desktop-wide libadwaita color-scheme preference.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    font-name = "JetBrainsMono Nerd Font 10";
  };

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
  programs.starship = {
    enable = true;
    enableBashIntegration = true;

    settings = {
      add_newline = false;

      format = "$directory$git_branch$git_status$character";

      directory = {
        truncation_length = 3;
        truncate_to_repo = false;
      };

      git_branch = {
        symbol = " ";
        format = "on [$symbol$branch]($style) ";
        style = "bold purple";
      };

      git_status = {
        format = "([$all_status$ahead_behind]($style)) ";
        style = "bold yellow";

        conflicted = "!";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        untracked = "?";
        stashed = "$";
        modified = "!";
        staged = "+";
        renamed = "»";
        deleted = "✘";
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
    };
  };
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };
}
