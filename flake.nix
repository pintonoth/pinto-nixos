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
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    umbriel = {
      url = "git+https://github.com/noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xdg-desktop-portal-umbriel = {
      url = "github:noctalia-dev/xdg-desktop-portal-umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";
    kineticwe = {
      url = "gitlab:theblackdon/kineticwe";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      noctalia,
      ...
    }@inputs:
    {
      # use "nixos", or your hostname as the name of the configuration
      # it's a better practice than "default" shown in the video
      nixosConfigurations = {
        pinto-nixos-kde = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/kde/configuration.nix
            ./hardware-configuration.nix
          ];
        };

        pinto-nixos-niri = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/niri/configuration.nix
            ./hardware-configuration.nix
            inputs.noctalia.nixosModules.default
            inputs.noctalia-greeter.nixosModules.default
          ];
        };

        pinto-nixos-umbriel = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/umbriel/configuration.nix
            ./hardware-configuration.nix
            inputs.noctalia.nixosModules.default
            inputs.noctalia-greeter.nixosModules.default
            inputs.umbriel.nixosModules.default
          ];
        };

        pinto-nixos-hyprland = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/hyprland/configuration.nix
            ./hardware-configuration.nix
            inputs.home-manager.nixosModules.default
          ];
        };
        pinto-nixos-kineticwe = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/kineticwe/configuration.nix
            ./hardware-configuration.nix
            inputs.home-manager.nixosModules.default
            inputs.kineticwe.nixosModules.default
          ];
        };
        pinto-nixos-cosmic = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/cosmic/configuration.nix
            ./hardware-configuration.nix
            inputs.home-manager.nixosModules.default
          ];
        };
      };
    };
}
