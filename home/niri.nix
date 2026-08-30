{ ... }:

{
  imports = [
    ./noctalia.nix
  ];

  xdg.configFile."niri".source = ./config/niri;
}
