{ pkgs, ... }:

{
  # GUI file manager
  programs.thunar.enable = true;
  programs.xfconf.enable = true;

  # Trash, removable drives, network locations, etc.
  services.gvfs.enable = true;

  # File thumbnails
  services.tumbler.enable = true;

  environment.systemPackages = with pkgs; [
    file
    ffmpegthumbnailer
  ];
}
