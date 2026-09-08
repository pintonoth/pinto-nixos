{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    umbriel = {
      url = "git+https://github.com/noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    xwayland-satellite = {
      url = "github:Supreeeme/xwayland-satellite/v0.8.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    persona = {
      url = "github:Yujonpradhananga/Persona-Quickshell/6bb02aa50f609be8047f67b8a9984274c91e2060";
      flake = false;
    };
    cava-monitor = {
      url = "github:Yujonpradhananga/Qt6-Cava-plugin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      mkSystem =
        profile:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            profile
            ./hardware-configuration.nix
          ];
        };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      checks.x86_64-linux.umbriel-config =
        self.nixosConfigurations.pinto-nixos-umbriel.config.home-manager.users.jensend.xdg.configFile."umbriel/config.toml".source;

      packages.x86_64-linux.persona-shell = import ./desktops/persona/package.nix {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        inherit inputs;
      };
      checks.x86_64-linux.persona = import ./desktops/persona/check.nix {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        persona = self.packages.x86_64-linux.persona-shell;
        hyprlandConfig =
          self.nixosConfigurations.pinto-nixos-persona.config.home-manager.users.jensend.xdg.configFile."hypr/hyprland.lua".source;
      };

      nixosConfigurations = {
        pinto-nixos-kde = mkSystem ./desktops/kde/nixos.nix;
        pinto-nixos-niri = mkSystem ./desktops/niri/nixos.nix;
        pinto-nixos-umbriel = mkSystem ./desktops/umbriel/nixos.nix;
        pinto-nixos-cosmic = mkSystem ./desktops/cosmic/nixos.nix;
        pinto-nixos-persona = mkSystem ./desktops/persona/nixos.nix;
      };
    };
}
