{ pkgs, ... }:

{
  imports = [
    ./desktop-common.nix
  ];

  home.packages = with pkgs; [
    adw-gtk3
  ];

  gtk = {
    enable = true;

    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };
}
