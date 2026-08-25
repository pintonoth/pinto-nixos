# Pinto's NixOS configuration

Personal NixOS configuration managed with Nix flakes and Home Manager. The primary setup is Umbriel with Noctalia and Noctalia Greeter.

## Primary configuration

Build the Umbriel configuration without activating it:

```bash
sudo nixos-rebuild build --flake .#pinto-nixos-umbriel
```

After reviewing the build result, activate it:

```bash
sudo nixos-rebuild switch --flake .#pinto-nixos-umbriel
```

The repository also contains these alternative desktop outputs:

| Setup | Flake output |
| --- | --- |
| Umbriel + Noctalia | `pinto-nixos-umbriel` |
| Niri + Noctalia | `pinto-nixos-niri` |
| KDE Plasma | `pinto-nixos-kde` |
| Hyprland | `pinto-nixos-hyprland` |
| COSMIC | `pinto-nixos-cosmic` |
| KineticWE | `pinto-nixos-kineticwe` |

## Repository layout

```text
pinto-nixos/
├── flake.nix                       # Inputs and NixOS configuration outputs
├── flake.lock                      # Locked dependency revisions
├── hardware-configuration.nix      # Machine-specific hardware configuration
├── hosts/
│   ├── common.nix                  # Settings shared by the desktop outputs
│   └── umbriel/configuration.nix   # Umbriel system and Home Manager entry point
├── modules/
│   ├── desktop/umbriel.nix         # Umbriel, Noctalia, greeter, and keyring
│   ├── system/                     # Audio, locale, network, drives, and packages
│   └── others/                     # File manager, gaming, maintenance, and virtualization
└── home/
    ├── desktop-common.nix           # Shared Home Manager and MIME settings
    ├── kitty.nix                    # Kitty configuration deployment
    ├── umbriel.nix                  # Umbriel user settings, cursor, and GTK theme
    └── config/
        ├── kitty/                   # Kitty configuration files
        └── umbriel/                 # Umbriel TOML configuration files
```

## Umbriel configuration

The Umbriel setup is divided between system-level and user-level configuration:

- `modules/desktop/umbriel.nix` enables Umbriel, Noctalia, Noctalia Greeter, the Umbriel portal, and GNOME Keyring integration.
- `home/umbriel.nix` configures the GTK theme and cursor, and deploys the Umbriel configuration through Home Manager.
- `home/config/umbriel/config.toml` contains the main compositor configuration.
- `home/config/umbriel/keybinds.toml` contains keyboard shortcuts.
- `home/config/umbriel/outputs.toml` contains monitor settings.
- `home/config/umbriel/windowrules.toml` contains application and workspace rules.

Umbriel loads the three supplemental TOML files through the `include.files` list in `config.toml`.

## Common changes

| Change | File |
| --- | --- |
| Umbriel, Noctalia, greeter, or portal | `modules/desktop/umbriel.nix` |
| Umbriel keybindings or layout | `home/config/umbriel/` |
| GTK theme or cursor | `home/umbriel.nix` |
| System packages | `modules/system/packages.nix` |
| Locale, input method, or printing | `modules/system/locale.nix` |
| Kitty settings | `home/config/kitty/kitty.conf` |
| Shared Home Manager settings | `home/desktop-common.nix` |
| Boot, hostname, user, or kernel | `hosts/common.nix` |

## Updating dependencies

Update every flake input:

```bash
nix flake update
```

To update only the Umbriel-specific dependencies:

```bash
nix flake update umbriel noctalia noctalia-greeter xdg-desktop-portal-umbriel
```

Review `flake.lock`, then build the Umbriel output before switching.

## Notes

- The system uses NixOS unstable.
- The configured hostname is `nixos` and the main user is `jensend`.
- Noctalia Greeter uses greetd and starts the Umbriel session by default.
- `hardware-configuration.nix` is specific to this machine and should be regenerated for different hardware.
- Do not change `system.stateVersion` or `home.stateVersion` merely when updating NixOS; they preserve compatibility with the original installation state.
