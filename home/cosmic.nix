{ pkgs, ... }:

{
  imports = [
    ./desktop-common.nix
  ];

  home.packages = with pkgs; [
    adw-gtk3
  ];
}
