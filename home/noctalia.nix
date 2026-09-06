{ lib, ... }:

{
  xdg.configFile."noctalia/config.toml".text =
    lib.replaceStrings [ "@wallpaper@" ] [ "${../assets/wallpapers/wallhaven-e82xxr.jpg}" ]
      (builtins.readFile ./config/noctalia/config.toml);
}
