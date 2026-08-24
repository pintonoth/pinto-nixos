# Pinto's NixOS configuration

My personal NixOS configuration, managed with Nix flakes and Home Manager.

It includes several desktop setups that share the same base system configuration:

- KDE Plasma
- Niri + Noctalia
- Umbriel + Noctalia
- Hyprland
- COSMIC
- KineticWE

## Quick start

Enter the configuration directory:

```bash
cd pinto-nixos
```

Build and switch to a desktop setup:

```bash
sudo nixos-rebuild switch --flake .#pinto-nixos-niri
```

Replace `pinto-nixos-niri` with the setup you want to use:

| Setup | Flake output |
| --- | --- |
| Niri + Noctalia | `pinto-nixos-niri` |
| Umbriel + Noctalia | `pinto-nixos-umbriel` |
| KDE Plasma | `pinto-nixos-kde` |
| Hyprland | `pinto-nixos-hyprland` |
| COSMIC | `pinto-nixos-cosmic` |
| KineticWE | `pinto-nixos-kineticwe` |

To only check whether a configuration builds:

```bash
sudo nixos-rebuild build --flake .#pinto-nixos-niri
```

## Repository layout

```text
pinto-nixos/
├── flake.nix                  # Flake inputs and available desktop setups
├── hardware-configuration.nix # Machine-specific hardware settings
├── hosts/
│   ├── common.nix             # Settings shared by every setup
│   └── <desktop>/             # One entry point per desktop setup
├── modules/
│   ├── system/                # Shared system settings: audio, network, drives, packages
│   ├── desktop/               # Desktop-specific system settings
│   └── others/                # Gaming, virtualization, maintenance, and file manager settings
└── home/
    ├── desktop-common.nix     # Shared user-level settings
    ├── niri.nix               # Niri user settings, GTK theme, cursor, and Niri config
    └── config/                # Application configuration files
```

## Where to make changes

- Add or remove system packages: `modules/system/packages.nix`
- Change shared system settings: `hosts/common.nix`
- Change Niri, Noctalia, portals, or Thunar: `modules/desktop/noctalia.nix`
- Change Niri keybindings and layout: `home/config/niri/config.kdl`
- Change Niri GTK theme or cursor: `home/niri.nix`
- Change Kitty: `home/kitty.nix` and `home/config/kitty/kitty.conf`

## Updating flake inputs

Update locked dependencies:

```bash
nix flake update
```

Then rebuild the setup you use:

```bash
sudo nixos-rebuild switch --flake .#pinto-nixos-niri
```

## Notes

- The shared hostname is currently `nixos`.
- The main user is `jensend`.
- This configuration uses the unstable Nixpkgs channel.
- `hardware-configuration.nix` is machine-specific. Do not copy it to another machine without regenerating it.
