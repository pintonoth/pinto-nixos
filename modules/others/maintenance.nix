{ config, pkgs, ... }:

{
  # Automated Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Optimize the Nix Store automatically (hard-links duplicate files)
  nix.settings.auto-optimise-store = true;

  # Enable automatic firmware updates for your hardware
  services.fwupd.enable = true;
}
