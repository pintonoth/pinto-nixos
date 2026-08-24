{ inputs, pkgs, ... }:

{
  programs.umbriel = {
    enable = true;
    portalPackage =
      inputs.xdg-desktop-portal-umbriel.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  programs.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "umbriel";

      appearance = {
        scheme = "Catppuccin";
        theme_mode = "dark";
        corner_radius_scale = 1.0;
      };

      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
        path = "${pkgs.bibata-cursors}/share/icons";
      };

      idle.timeout = 300;
    };
  };

  programs.dconf.enable = true;
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  programs.bash.shellAliases.fm = "yazi";

  environment.systemPackages = with pkgs; [
    yazi
    file
    ffmpegthumbnailer
  ];
}
