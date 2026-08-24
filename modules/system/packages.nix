{
  inputs,
  config,
  pkgs,
  ...
}:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Core applications
  # programs.firefox.enable = true;
  programs.nix-ld.enable = true;
  programs.bash = {
    enable = true;
    interactiveShellInit = ''
      fastfetch --config examples/17.jsonc
    '';
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    (chromium.override {
      enableWideVine = true;
      commandLineArgs = [
        "--enable-features=AcceleratedVideoEncoder"
        "--enable-features=VerticalTabs"
        "--ignore-gpu-blocklist"
        "--enable-zero-copy"
      ];
    })
    btop
    discord
    equibop
    fastfetch
    ffmpeg
    git
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    heroic
    kitty
    mpv
    nil
    nixd
    lmstudio
    obsidian
    playerctl
    pika-backup
    protonup-qt
    qbittorrent
    spotify
    steam
    vlc
    zed-editor
    whatsapp-electron
    xwayland-satellite
  ];
}
