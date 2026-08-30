{ inputs, pkgs, ... }:

{
  # environment.sessionVariables.NIXOS_OZONE_WL = "1";
  programs.umbriel.enable = true;
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  programs.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "umbriel";

      appearance = {
        scheme = "Synced";
      };

      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
        path = "${pkgs.bibata-cursors}/share/icons";
      };

      idle.timeout = 300;
    };
  };

  services.gnome.gnome-keyring.enable = true;

  security.pam.services.greetd.enableGnomeKeyring = true;
}
