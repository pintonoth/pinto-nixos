{
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
  services.flatpak = {
    enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    steam
    xwayland-satellite
  ];
}
