{ config, lib, pkgs, ... }:

let
  # Validate the complete static configuration together. Noctalia supplies the
  # theme at runtime, so only the validation copy gets an empty placeholder.
  validatedConfig = pkgs.runCommand "umbriel-config" { } ''
    mkdir config
    cp ${./config/umbriel}/*.toml config/
    touch config/noctalia.toml
    ${lib.getExe config.programs.umbriel.package} validate -c config/config.toml
    cp config/config.toml $out
  '';
in
{
  imports = [
    ./noctalia.nix
  ];

  programs.umbriel = {
    enable = true;
    package = pkgs.umbriel;
    settings = ./config/umbriel/config.toml;
    validateConfig = true;
  };

  xdg.configFile = {
    # Replace the upstream single-file validator with one that sees the includes.
    # Install only config.toml; the runtime theme must remain writable by Noctalia.
    "umbriel/config.toml".source = lib.mkIf config.programs.umbriel.validateConfig (
      lib.mkForce validatedConfig
    );
    "umbriel/keybinds.toml".source = ./config/umbriel/keybinds.toml;
    "umbriel/outputs.toml".source = ./config/umbriel/outputs.toml;
    "umbriel/windowrules.toml".source = ./config/umbriel/windowrules.toml;
    "umbriel/appearance.toml".source = ./config/umbriel/appearance.toml;
    "umbriel/animation.toml".source = ./config/umbriel/animation.toml;
    "umbriel/layout.toml".source = ./config/umbriel/layout.toml;
  };
}
