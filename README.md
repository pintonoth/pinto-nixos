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

The four outputs are alternative desktop configurations for the same
`x86_64-linux` machine. Select one by its flake output name:

| Setup | Flake output | System entry point | Greeter |
| --- | --- | --- | --- |
| Umbriel + Noctalia | `pinto-nixos-umbriel` | `desktops/umbriel/nixos.nix` | Noctalia Greeter |
| Niri + Noctalia | `pinto-nixos-niri` | `desktops/niri/nixos.nix` | Noctalia Greeter |
| KDE Plasma | `pinto-nixos-kde` | `desktops/kde/nixos.nix` | SDDM |
| COSMIC | `pinto-nixos-cosmic` | `desktops/cosmic/nixos.nix` | COSMIC Greeter |

All outputs share the hostname `nixos`, user `jensend`, hardware configuration,
system modules, and common Home Manager settings. Selecting an output does not
require changing the hostname or editing the flake.

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
└── desktops/umbriel/nixos.nix
    ├── hosts/common.nix
    │   ├── Home Manager, Stylix, and Flatpak modules
    │   ├── overlays/default.nix
    │   ├── modules/default.nix
    │   │   ├── modules/system/*
    │   │   └── modules/others/*
    │   └── home/desktop-common.nix
    │       └── home/kitty.nix
    │
    ├── modules/desktop/noctalia.nix
    │   ├── upstream Noctalia NixOS module
    │   └── upstream Noctalia Greeter NixOS module
    ├── modules/desktop/xdg-portal.nix
    ├── upstream Umbriel NixOS module
    ├── upstream Umbriel Home Manager module
    │
    └── desktops/umbriel/home.nix
        ├── home/noctalia.nix
        │   └── home/config/noctalia/config.toml
        │
        └── home/config/umbriel/*
```

Each `desktops/<name>/nixos.nix` is a system entry point that imports the common
host configuration, its desktop dependencies, and its adjacent Home Manager
module where needed. COSMIC uses only the shared Home Manager configuration.
The `modules/` directory contains shared system configuration, while `home/`
contains shared Home Manager modules and raw configuration files deployed under
`~/.config`. Definitions from `home/desktop-common.nix` and the selected
desktop's Home Manager module are merged for the `jensend` user. The flake's
`mkSystem` helper combines each desktop entry point with this machine's hardware
configuration.

The shared Home Manager configuration uses the system package set through
`useGlobalPkgs` and installs user packages through `useUserPackages`. KDE adds
a Dolphin default-file-manager override; Niri and Umbriel add compositor and
Noctalia configuration. COSMIC has no separate Home Manager file.

`overlays/default.nix` supplies the pinned Xwayland Satellite package and
overrides the Umbriel package to use that same dependency. Both Umbriel modules
select `pkgs.umbriel`, keeping the system compositor and user configuration
validator on the same package.

## Repository layout

```text
pinto-nixos/
├── flake.nix                       # Inputs and NixOS configuration outputs
├── flake.lock                      # Locked dependency revisions
├── hardware-configuration.nix      # Machine-specific hardware configuration
├── hosts/
│   └── common.nix                  # Settings shared by the desktop outputs
├── desktops/
│   ├── cosmic/
│   │   └── nixos.nix              # COSMIC session and greeter
│   ├── kde/
│   │   ├── nixos.nix              # Plasma session and SDDM
│   │   └── home.nix               # Dolphin MIME default
│   ├── niri/
│   │   ├── nixos.nix              # Niri session and greeter appearance
│   │   └── home.nix               # Niri and Noctalia configuration deployment
│   └── umbriel/
│       ├── nixos.nix              # Umbriel session, greeter, and keyring
│       └── home.nix               # Umbriel validation and configuration deployment
├── modules/
│   ├── default.nix                # Imports system/ and others/
│   ├── desktop/
│   │   ├── noctalia.nix           # Shared Noctalia services and greeter settings
│   │   └── xdg-portal.nix         # Shared GTK portal fallback
│   ├── system/
│   │   ├── default.nix            # System imports, fonts, and Stylix theme
│   │   ├── audio.nix              # PipeWire and RTKit
│   │   ├── drives.nix             # Additional machine-specific NTFS mounts
│   │   ├── locale.nix             # Time zone, locales, and Fcitx5 input methods
│   │   ├── network.nix            # SSH, NordVPN, DNS, and networking rules
│   │   └── packages.nix           # Applications, program settings, Flatpak reference
│   └── others/
│       ├── default.nix            # Imports the modules below
│       ├── file-manager.nix       # Thunar and file-management services
│       ├── gaming.nix             # Steam, GameMode, and graphics support
│       ├── maintenance.nix        # Garbage collection, store optimization, fwupd
│       └── virtualization.nix     # Libvirt, QEMU, virt-manager, and related packages
├── overlays/
│   └── default.nix                # Umbriel and Xwayland Satellite package selection
└── home/
    ├── desktop-common.nix          # Shared Home Manager, shell, and MIME settings
    ├── kitty.nix                   # Kitty configuration deployment
    ├── noctalia.nix                # Noctalia configuration deployment
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

- `desktops/umbriel/nixos.nix` enables the system-level Umbriel session and
  GNOME Keyring integration, imports shared Noctalia and greeter settings, and
  connects the Umbriel Home Manager modules. The upstream
  Umbriel NixOS module installs the compositor, registers the display-manager
  session, and configures its portal and service.
- `desktops/umbriel/home.nix` enables the upstream Umbriel Home Manager module
  so it can validate and deploy the user's main compositor configuration. It
  also deploys the supplemental TOML files.
- `home/noctalia.nix` deploys `home/config/noctalia/config.toml` to
  `~/.config/noctalia/config.toml` for both the Umbriel and Niri profiles.
- `home/config/umbriel/config.toml` contains the main compositor configuration.
- `home/config/umbriel/keybinds.toml` contains keyboard shortcuts.
- `home/config/umbriel/outputs.toml` contains monitor settings.
- `home/config/umbriel/windowrules.toml` contains application and workspace rules.

Umbriel loads the six supplemental TOML files and the runtime-generated
`noctalia.toml` through the `include.files` list in `config.toml`.

The Home Manager module validates a build-time copy of the full configuration,
with an empty `noctalia.toml` placeholder. It deploys the tracked TOML files
individually so Noctalia can still write its generated theme under
`~/.config/umbriel/`. Keep this directory writable instead of replacing the
whole directory with a store symlink.

Kitty has a similar requirement: `home/kitty.nix` copies `kitty.conf` during
Home Manager activation as a writable file. That configuration includes
`themes/noctalia.conf`. Edit the repository's Kitty configuration for persistent
changes; activation installs it again.

The shared greeter module defines the Bibata cursor and 300-second idle timeout.
Umbriel selects the `umbriel` session with the `Synced` appearance scheme;
Niri selects `niri` with Catppuccin dark appearance. Umbriel's upstream NixOS
import has a small wrapper to preserve package-list ordering after the module
reorganization.

## Common changes

| Change | File |
| --- | --- |
| Umbriel session or greeter appearance | `desktops/umbriel/nixos.nix` |
| Niri session or greeter appearance | `desktops/niri/nixos.nix` |
| KDE session or greeter | `desktops/kde/nixos.nix` |
| COSMIC session or greeter | `desktops/cosmic/nixos.nix` |
| Shared Noctalia and greeter services | `modules/desktop/noctalia.nix` |
| Noctalia panel settings | `home/config/noctalia/config.toml` |
| Umbriel keybindings or layout | `home/config/umbriel/` |
| Umbriel validation or file deployment | `desktops/umbriel/home.nix` |
| Niri keybindings or layout | `home/config/niri/config.kdl` |
| Shared theme, cursor, or fonts | `modules/system/default.nix` |
| Desktop portal defaults | `modules/desktop/xdg-portal.nix` |
| System packages | `modules/system/packages.nix` |
| Steam, GameMode, or gaming graphics | `modules/others/gaming.nix` |
| VPN service, DNS, or networking rules | `modules/system/network.nix` |
| Additional storage mounts | `modules/system/drives.nix` |
| File-manager services | `modules/others/file-manager.nix` |
| Virtual machines | `modules/others/virtualization.nix` |
| Garbage collection or firmware updates | `modules/others/maintenance.nix` |
| Locale, input method, or printing | `modules/system/locale.nix` |
| Kitty settings | `home/config/kitty/kitty.conf` |
| Shared Home Manager settings | `home/desktop-common.nix` |
| Boot, hostname, user, or kernel | `hosts/common.nix` |
| Umbriel or Xwayland Satellite package overrides | `overlays/default.nix` |

## Checking changes

Evaluate all four desktop outputs without building or updating the lock file:

```bash
nix flake check --no-build --no-update-lock-file
```

Add `--offline` when all locked inputs are already available locally. Evaluation
checks module composition, options, and assertions; it does not run Umbriel's
build-time configuration validator or test a live desktop session. Build the
selected output before activating it, using the commands above.

New files must be tracked by Git to be included in normal Git-backed flake
evaluation. For a structural refactor, compare each output's system derivation
before and after the change; for example:

```bash
nix eval --raw --no-update-lock-file .#nixosConfigurations.pinto-nixos-umbriel.config.system.build.toplevel.drvPath
```

Matching derivation paths confirm that the refactor generates the same system
build instructions with the same locked inputs.

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
- Noctalia Greeter uses greetd for the Umbriel and Niri outputs, with the session selected by the desktop entry point.
- The `nix-flatpak` input and module import are retained. The commented Flatpak configuration in `modules/system/packages.nix` is intentionally kept as a reference for future use; it currently enables no Flatpak service or app installation.
- `hardware-configuration.nix` is specific to this machine and should be regenerated for different hardware.
- Review the machine-specific UUIDs and ownership options in `modules/system/drives.nix` when adapting this repository to another machine.
- Do not change `system.stateVersion` or `home.stateVersion` merely when updating NixOS; they preserve compatibility with the original installation state.
