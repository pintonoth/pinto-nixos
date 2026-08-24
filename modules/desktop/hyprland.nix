{ ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  }; # enable Hyprland

  # Optional, hint Electron apps to use Wayland:
  # environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
