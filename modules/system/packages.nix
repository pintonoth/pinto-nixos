{ inputs, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (import ../../overlays { inherit inputs; })
  ];

  programs.dconf.enable = true;

  # Core applications
  # programs.firefox.enable = true;
  programs.nix-ld.enable = true;
  programs.gpu-screen-recorder.enable = true;
  programs.bash = {
    enable = true;
  };
  programs.solaar.enable = true;
  programs.chromium = {
    enable = true;
    extensions = [
      "nngceckbapebfimnlniiiahkandclblb" # bitwarden
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # ublokc
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # dark reader
      "jdpblpklojajpopllbckephjndibljbc" # twitch auto clicker
    ];
  };
  hardware.logitech.wireless.enable = true;
  # Flatpak configurations
  # services.flatpak = {
  #   enable = true;
  #   update.auto = {
  #     enable = true;
  #     onCalendar = "weekly";
  #   };
  #   remotes = [
  #     {
  #       name = "flathub";
  #       location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
  #     }
  #     {
  #       name = "mixtapes";
  #       location = "https://m-obeid.github.io/Mixtapes/mixtapes.flatpakrepo";
  #     }
  #   ];

  #   packages = [
  #     {
  #       appId = "com.pocoguy.Muse";
  #       origin = "mixtapes";
  #     }
  #   ];
  # };

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    (chromium.override {
      enableWideVine = true;
      commandLineArgs = [
        "--enable-features=AcceleratedVideoEncoder"
        "--ignore-gpu-blocklist"
        "--enable-zero-copy"
      ];
    })
    btop
    discord
    equibop
    fastfetch
    ffmpeg
    fragments
    git
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    gpu-screen-recorder-gtk
    heroic
    kitty
    libayatana-appindicator
    libreoffice-stable
    # lmstudio
    mpv
    nil
    nixd
    nordvpn
    obsidian
    opencode
    pika-backup
    playerctl
    protonplus
    spotify
    vlc
    xwayland-satellite
    unzip
    zapzap
    zed-editor
    zip
    xarchiver
  ];
}
