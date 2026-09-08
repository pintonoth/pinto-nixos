{
  osConfig,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  persona = import ./package.nix { inherit pkgs inputs; };
  kittyConfig = pkgs.writeText "persona-kitty.conf" (
    builtins.replaceStrings
      [ "# Generated and updated by Noctalia's built-in Kitty template.\ninclude themes/noctalia.conf" ]
      [ (builtins.readFile ./kitty-theme.conf) ]
      (builtins.readFile ../../home/config/kitty/kitty.conf)
  );
in
{
  home.packages = [
    persona
    pkgs.playerctl
    pkgs.brightnessctl
  ];
  xdg.configFile."quickshell/persona".source = persona.source;

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = true;
    extraConfig =
      builtins.replaceStrings
        [ "@persona@" "@cursorTheme@" "@cursorSize@" ]
        [
          "${persona}/bin/persona-shell"
          osConfig.stylix.cursor.name
          (toString osConfig.stylix.cursor.size)
        ]
        (builtins.readFile ./hyprland.lua);
  };

  services.hyprpolkitagent.enable = true;
  # Retain the shared writable Kitty deployment, with a self-contained theme.
  home.activation.installKittyConfig = lib.mkForce (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD install -D -m 0644 ${kittyConfig} "$HOME/.config/kitty/kitty.conf"
    ''
  );
}
