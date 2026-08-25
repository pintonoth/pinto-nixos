{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    inputs.home-manager.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ../modules
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.jensend = import ../home/desktop-common.nix;
  };

  # Experimental features enabled for future flake readiness
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # UEFI Bootloader configurations
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
  boot.loader = {
    efi.canTouchEfiVariables = true;

    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
    };
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Networking options
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  programs.dconf.enable = true;

  # Define user account "jensend"
  users.users."jensend" = {
    isNormalUser = true;
    description = "pinto";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  system.stateVersion = "26.05";
}
