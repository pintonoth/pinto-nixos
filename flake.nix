{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs"; # this line is optional, prevents downloading two versions of nixpkgs but disables cache
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kineticwe = {
      url = "gitlab:theblackdon/kineticwe";
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
            inputs.home-manager.nixosModules.default
          ];
        };

        pinto-nixos-niri = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/niri/configuration.nix
            ./hardware-configuration.nix
            inputs.home-manager.nixosModules.default
            inputs.noctalia.nixosModules.default

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
