{ ... }:

{
  imports = [
    ../../home/noctalia.nix
  ];

  xdg.configFile."niri".source = ../../home/config/niri;
}
