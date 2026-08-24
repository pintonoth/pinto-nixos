{ inputs, pkgs, ... }:
{
  programs.noctalia = {
    enable = true;

    # Enables NetworkManager, Bluetooth, UPower, and a power profile service.
    recommendedServices.enable = true;
  };
  programs.niri.enable = true;
  programs.dconf.enable = true;
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  programs.bash.shellAliases = {
    fm = "yazi";
  };

  environment.systemPackages = with pkgs; [
    yazi
    file
    ffmpegthumbnailer
  ];

  # XDG desktop portals
  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];

    config.common.default = [ "gtk" ];
  };
}
