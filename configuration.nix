{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.default
    inputs.stylix.nixosModules.stylix
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ./modules
  ];

  system.stateVersion = "26.05";
}
