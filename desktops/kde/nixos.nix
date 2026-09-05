{ ... }:
{
  imports = [
    ../../hosts/common.nix
  ];

  home-manager.users.jensend = import ./home.nix;

  services.desktopManager.plasma6.enable = true;
  services.xserver.enable = false;
  services.displayManager.sddm.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
