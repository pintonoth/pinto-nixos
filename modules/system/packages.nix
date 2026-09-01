{
  inputs,
  pkgs,
  ...
}:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Core applications
  # programs.firefox.enable = true;
  programs.nix-ld.enable = true;
  programs.gpu-screen-recorder.enable = true;
  programs.bash = {
    enable = true;
  };
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;
    dedicatedServer.openFirewall = true;
  };
  programs.solaar.enable = true;
  hardware.logitech.wireless.enable = true;
  services.nordvpn.enable = true;
  # Flatpak configurations
  services.flatpak = {
    enable = true;
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
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
  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    btop
    discord
    equibop
    fastfetch
    faugus-launcher
    ffmpeg
    git
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    gpu-screen-recorder-gtk
    kitty
    libayatana-appindicator
    libreoffice-stable
    # lmstudio
    mpv
    nil
    nixd
    nordvpn
    obsidian
    pika-backup
    playerctl
    protonplus
    qbittorrent
    solaar
    spotify
    steam
    vlc
    xwayland-satellite
    unzip
    zed-editor
    zip
    xarchiver
  ];
}
