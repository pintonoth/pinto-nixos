{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Validate the complete static configuration together. Noctalia supplies the
  # theme at runtime, so only the validation copy gets an empty placeholder.
  validatedConfig = pkgs.runCommand "umbriel-config" { } ''
    mkdir config
    cp ${../../home/config/umbriel}/*.toml config/
    touch config/noctalia.toml
    ${lib.getExe config.programs.umbriel.package} validate -c config/config.toml
    cp config/config.toml $out
  '';
in
{
  imports = [
    ../../home/noctalia.nix
  ];

  programs.umbriel = {
    enable = true;
    package = pkgs.umbriel;
    settings = ../../home/config/umbriel/config.toml;
  };

  xdg.configFile = {
    # Provide build-time validation independently of the upstream module.
    # Install only config.toml; the runtime theme must remain writable by Noctalia.
    "umbriel/config.toml".source = lib.mkForce validatedConfig;
    "umbriel/keybinds.toml".source = ../../home/config/umbriel/keybinds.toml;
    "umbriel/outputs.toml".source = ../../home/config/umbriel/outputs.toml;
    "umbriel/windowrules.toml".source = ../../home/config/umbriel/windowrules.toml;
    "umbriel/appearance.toml".source = ../../home/config/umbriel/appearance.toml;
    "umbriel/animation.toml".source = ../../home/config/umbriel/animation.toml;
    "umbriel/layout.toml".source = ../../home/config/umbriel/layout.toml;
  };
}
