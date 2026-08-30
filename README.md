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
| COSMIC | `pinto-nixos-cosmic` |

## Configuration flow

`nixos-rebuild` starts from the selected output in `flake.nix`. Nix then
evaluates and merges the imported modules; the imports are a module graph, not
an imperative sequence. For the primary Umbriel output, that graph is:

```text
nixos-rebuild ... .#pinto-nixos-umbriel
                         │
                         ▼
flake.nix
├── hardware-configuration.nix
├── external NixOS modules
│   ├── Noctalia
│   ├── Noctalia Greeter
│   └── Umbriel
│
└── hosts/umbriel/configuration.nix
    ├── hosts/common.nix
    │   ├── Home Manager, Stylix, and Flatpak modules
    │   ├── modules/default.nix
    │   │   ├── modules/system/*
    │   │   └── modules/others/*
    │   └── home/desktop-common.nix
    │       └── home/kitty.nix
    │
    ├── modules/desktop/umbriel.nix
    ├── modules/desktop/xdg-portal.nix
    │
    └── home/umbriel.nix
        ├── home/noctalia.nix
        │   └── home/config/noctalia/config.toml
        │
        └── home/config/umbriel/*
```

The `modules/` branch contains system-level NixOS configuration. The `home/`
branch contains user-level Home Manager configuration and deploys files under
`~/.config`. Definitions from `home/desktop-common.nix` and the selected
desktop's Home Manager module are merged for the `jensend` user.

## Repository layout

```text
pinto-nixos/
├── flake.nix                       # Inputs and NixOS configuration outputs
├── flake.lock                      # Locked dependency revisions
├── hardware-configuration.nix      # Machine-specific hardware configuration
├── hosts/
│   ├── common.nix                  # Settings shared by the desktop outputs
│   ├── cosmic/configuration.nix    # COSMIC host entry point
│   ├── kde/configuration.nix       # KDE host entry point
│   ├── niri/configuration.nix      # Niri and Noctalia host entry point
│   └── umbriel/configuration.nix   # Umbriel and Noctalia host entry point
├── modules/
│   ├── desktop/                    # Desktop, greeter, and portal modules
│   ├── system/                     # Audio, locale, network, drives, and packages
│   └── others/                     # File manager, gaming, maintenance, and virtualization
└── home/
    ├── desktop-common.nix          # Shared Home Manager, shell, and MIME settings
    ├── kitty.nix                   # Kitty configuration deployment
    ├── noctalia.nix                # Noctalia configuration deployment
    ├── umbriel.nix                 # Umbriel configuration deployment
    └── config/
        ├── kitty/                  # Kitty configuration files
        ├── niri/                   # Niri configuration
        ├── noctalia/               # Noctalia TOML configuration
        └── umbriel/                # Umbriel TOML configuration files
```

## Umbriel configuration

The Umbriel setup is divided between system-level and user-level configuration.
Both levels have a `programs.umbriel.enable` option, but they belong to separate
module systems and perform different jobs:

- `modules/desktop/umbriel.nix` enables the system-level Umbriel session,
  Noctalia, Noctalia Greeter, and GNOME Keyring integration. The upstream
  Umbriel NixOS module installs the compositor, registers the display-manager
  session, and configures its portal and service.
- `home/umbriel.nix` enables the upstream Umbriel Home Manager module so it can
  validate and deploy the user's main compositor configuration. It also deploys
  the supplemental TOML files.
- `home/noctalia.nix` deploys `home/config/noctalia/config.toml` to
  `~/.config/noctalia/config.toml` for both the Umbriel and Niri profiles.
- `home/config/umbriel/config.toml` contains the main compositor configuration.
- `home/config/umbriel/keybinds.toml` contains keyboard shortcuts.
- `home/config/umbriel/outputs.toml` contains monitor settings.
- `home/config/umbriel/windowrules.toml` contains application and workspace rules.

Umbriel loads `animation.toml`, `appearance.toml`, `keybinds.toml`,
`layout.toml`, `outputs.toml`, and `windowrules.toml` through the `include.files`
list in `config.toml`.

## Common changes

| Change | File |
| --- | --- |
| Umbriel, Noctalia, or greeter services | `modules/desktop/umbriel.nix` |
| Noctalia panel settings | `home/config/noctalia/config.toml` |
| Umbriel keybindings or layout | `home/config/umbriel/` |
| Shared theme or cursor | `modules/system/default.nix` |
| Desktop portal defaults | `modules/desktop/xdg-portal.nix` |
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
nix flake update umbriel noctalia noctalia-greeter
```

Review `flake.lock`, then build the Umbriel output before switching.

## Notes

- The system uses NixOS unstable.
- The configured hostname is `nixos` and the main user is `jensend`.
- Noctalia Greeter uses greetd and starts the Umbriel session by default.
- `hardware-configuration.nix` is specific to this machine and should be regenerated for different hardware.
- Do not change `system.stateVersion` or `home.stateVersion` merely when updating NixOS; they preserve compatibility with the original installation state.
