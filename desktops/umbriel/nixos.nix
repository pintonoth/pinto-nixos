{ inputs, pkgs, ... }:

{
  imports = [
    ../../configuration.nix
    ../../modules/desktop/noctalia.nix
    ../../modules/desktop/xdg-portal.nix
    # Match the nesting of Noctalia's upstream imports to preserve package order.
    { imports = [ inputs.umbriel.nixosModules.default ]; }
  ];

  home-manager.sharedModules = [ inputs.umbriel.homeModules.default ];
  home-manager.users.jensend = import ./home.nix;

  programs.umbriel = {
    enable = true;
    package = pkgs.umbriel;
  };

  programs.noctalia-greeter.settings = {
    session.default = "umbriel";

    appearance = {
      scheme = "Synced";
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
}
