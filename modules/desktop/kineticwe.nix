{ pkgs, inputs, ... }:
{
  programs.kineticwe.enable = true;
  services.desktopManager.plasma6.enable = true;
  # XDG desktop portals
  # xdg.portal = {
  #   enable = true;

  #   extraPortals = [
  #     pkgs.xdg-desktop-portal-kde
  #   ];

  #   config.common.default = [ "kde" ];
  # };
}
