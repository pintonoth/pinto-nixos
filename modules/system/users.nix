{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.jensend = import ../../home/desktop-common.nix;
  };

  # Define user account "jensend"
  users.users."jensend" = {
    isNormalUser = true;
    description = "pinto";
    extraGroups = [
      "networkmanager"
      "wheel"
      "nordvpn"
    ];
    # Preserve the original order before Home Manager's package environment.
    packages = lib.mkBefore [
      pkgs.kdePackages.kate
    ];
  };
}
