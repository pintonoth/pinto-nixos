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

The five outputs are alternative desktop configurations for the same
`x86_64-linux` machine. Select one by its flake output name:

| Setup | Flake output | System entry point | Greeter |
| --- | --- | --- | --- |
| Umbriel + Noctalia | `pinto-nixos-umbriel` | `desktops/umbriel/nixos.nix` | Noctalia Greeter |
| Niri + Noctalia | `pinto-nixos-niri` | `desktops/niri/nixos.nix` | Noctalia Greeter |
| KDE Plasma | `pinto-nixos-kde` | `desktops/kde/nixos.nix` | SDDM |
| COSMIC | `pinto-nixos-cosmic` | `desktops/cosmic/nixos.nix` | COSMIC Greeter |
| Hyprland + Persona | `pinto-nixos-persona` | `desktops/persona/nixos.nix` | Noctalia Greeter |

All outputs share the hostname `nixos`, user `jensend`, hardware configuration,
system modules, and common Home Manager settings. Selecting an output does not
require changing the hostname or editing the flake.

## Persona configuration

The optional Persona profile runs Hyprland with the
[Persona Quickshell theme](https://github.com/Yujonpradhananga/Persona-Quickshell).
It includes the animated wallpaper, Cava visualizer, media widget, clock,
calendar, application launcher, information panels, screen filters, and power
menu. It uses Noctalia Greeter for login. Additional notification, locking,
screenshot, and network/Bluetooth settings applications are not included in
this profile.

Build and validate before activating:

```bash
nix build --no-link .#checks.x86_64-linux.persona
sudo nixos-rebuild build --flake .#pinto-nixos-persona
```

To activate the built configuration, then enter a fresh Hyprland session:

```bash
sudo nixos-rebuild switch --flake .#pinto-nixos-persona
```

Save your work before switching desktop profiles, because the display-manager
change can end the current session. To return to the primary desktop, build
and switch `.#pinto-nixos-umbriel` using the commands at the top of this file.
The previous NixOS generation is also available from the boot menu.

`desktops/persona/hyprland.lua` configures HDMI-A-1 at 3840×2160, 120 Hz,
scale 2, with automatic configuration for other outputs. Shortcuts include
Super+T for Kitty, Super+E for Thunar, Super+Space for the launcher, Super+Q
to close a window, Super+V to toggle floating, Super+F to maximize, and
Super+Shift+F for fullscreen. Super+arrow keys change focus;
Super+Ctrl+arrows move windows. Super+1–9 changes workspace, and
Super+Ctrl+1–9 moves a window there. Media keys control PipeWire/playerctl.
Backlight shortcuts are enabled only when a supported backlight exists;
HDMI brightness through DDC/CI is not configured.

Persona's sources and Cava plugin are pinned through the flake. The package
supplies missing fonts, rebuilds wallpaper shaders with the pinned Qt, and
applies local compatibility fixes. The wrapper keeps the plugin and multimedia
imports local to Persona. Home Manager also exposes the packaged configuration
at `~/.config/quickshell/persona`; edit the tracked package/patches for lasting
changes. Kitty uses a static Persona palette in this profile.

Hyprland starts `persona-shell` once. Useful commands within that session:

```bash
persona-shell ipc call searchapp toggle
persona-shell list
persona-shell log
```

To restart after a shell failure, run `persona-shell`; the wrapper prevents
duplicate instances of the same configuration. To build just the shell, use
`nix build --no-link .#persona-shell`. The Persona revision is explicit in
`flake.nix`: change that revision and run `nix flake lock` to update it. Update
the Cava plugin separately with `nix flake update cava-monitor`, then rerun
the checks and full profile build.

The Persona check validates Hyprland's generated Lua configuration, packaged
assets, QML startup, launcher IPC, keyboard application launching, and duplicate
instance prevention in a headless Wayland session at 4K/scale 2. Its output
contains logs and desktop/launcher screenshots. It does not test the physical
display, greeter login, real audio playback, screen filters in Hyprland, or
shutdown/reboot. Check those in a fresh Hyprland session; inspect
`hyprctl configerrors` and `persona-shell log` if something fails. With no
active MPRIS player the media widget displays its idle state; Cava requires a
running PipeWire session and audio output.

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
    ├── configuration.nix
    │   ├── Home Manager, Stylix, and Flatpak modules
    │   └── modules/default.nix
    │       ├── modules/system/default.nix
    │       │   ├── packages.nix → overlays/default.nix
    │       │   ├── users.nix → home/desktop-common.nix → home/kitty.nix
    │       │   └── boot, locale, network, drives, and audio modules
    │       └── modules/others/*
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
        │   ├── home/config/noctalia/config.toml
        │   └── assets/wallpapers/wallhaven-e82xxr.jpg
        │
        └── home/config/umbriel/*
```

Each `desktops/<name>/nixos.nix` is a system entry point that imports the common
root `configuration.nix`, its desktop dependencies, and its adjacent Home Manager
module where needed. COSMIC uses only the shared Home Manager configuration.
The `modules/` directory contains shared system configuration, while `home/`
contains shared Home Manager modules and raw configuration files deployed under
`~/.config`. Definitions from `home/desktop-common.nix` and the selected
desktop's Home Manager module are merged for the `jensend` user. The flake's
`mkSystem` helper combines each desktop entry point with this machine's hardware
configuration.

The root `configuration.nix` connects external modules to the shared system
modules and sets `system.stateVersion`. Shared settings live in modules grouped
by responsibility: boot and kernel in `boot.nix`, account and Home Manager
integration in `users.nix`, networking in `network.nix`, package overlays and
program settings in `packages.nix`, and Nix settings in `maintenance.nix`.
The user module explicitly keeps its account packages before Home Manager's
package environment to preserve the original package order after the split.

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
├── configuration.nix               # External/shared module imports and state version
├── hardware-configuration.nix      # Machine-specific hardware configuration
├── assets/
│   └── wallpapers/
│       └── wallhaven-e82xxr.jpg     # Bundled Noctalia wallpaper
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
│   │   ├── boot.nix               # Bootloader and kernel
│   │   ├── drives.nix             # Additional machine-specific NTFS mounts
│   │   ├── locale.nix             # Time zone, locales, and Fcitx5 input methods
│   │   ├── network.nix            # Hostname, NetworkManager, SSH, NordVPN, and DNS
│   │   ├── packages.nix           # Overlays, applications, dconf, Flatpak reference
│   │   └── users.nix              # User account and Home Manager integration
│   └── others/
│       ├── default.nix            # Imports the modules below
│       ├── file-manager.nix       # Thunar and file-management services
│       ├── gaming.nix             # Steam, GameMode, and graphics support
│       ├── maintenance.nix        # Nix settings, garbage collection, fwupd
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
- `home/noctalia.nix` generates `~/.config/noctalia/config.toml` from the repository
  TOML file for both the Umbriel and Niri profiles, substituting the bundled
  wallpaper's Nix store path.
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

The shared greeter module reads the cursor theme, size, and package from Stylix
in `modules/system/default.nix`, and defines the 300-second idle timeout.
Umbriel selects the `umbriel` session with the `Synced` appearance scheme;
Niri selects `niri` with Catppuccin dark appearance. Umbriel's upstream NixOS
import has a small wrapper to preserve package-list ordering after the module
reorganization.

Window transparency and blur are configured in
`home/config/umbriel/windowrules.toml`. The active/inactive rules set focused
windows to full opacity and unfocused windows to 95% opacity. These rules appear
after the general and application-specific rules, so their opacity values take
precedence. Blur settings are controlled separately by the earlier rules.

## Wallpaper

`assets/wallpapers/wallhaven-e82xxr.jpg` is the wallpaper bundled with the
Umbriel and Niri configurations. `home/noctalia.nix` replaces `@wallpaper@` in
the Noctalia TOML template with the image's Nix store path for the default,
last-used, and `HDMI-A-1` wallpaper settings. The image is included in the
configuration's store dependencies; the original file in `~/Pictures/` is
no longer required by this configuration.

To change the bundled wallpaper, replace the repository image, or add a new
image under `assets/wallpapers/` and update its reference in `home/noctalia.nix`.
Keep the `@wallpaper@` placeholders in the TOML template and track any new image
with Git. Build and activate the selected desktop output, then let Noctalia
reload its configuration or start a new session. A build alone does not change
the running desktop. KDE and COSMIC do not use this Noctalia wallpaper setup.

## Common changes

| Change | File |
| --- | --- |
| Umbriel session or greeter appearance | `desktops/umbriel/nixos.nix` |
| Niri session or greeter appearance | `desktops/niri/nixos.nix` |
| KDE session or greeter | `desktops/kde/nixos.nix` |
| COSMIC session or greeter | `desktops/cosmic/nixos.nix` |
| Shared Noctalia and greeter services | `modules/desktop/noctalia.nix` |
| Noctalia panel settings | `home/config/noctalia/config.toml` |
| Bundled wallpaper | `assets/wallpapers/wallhaven-e82xxr.jpg` and `home/noctalia.nix` |
| Umbriel keybindings or layout | `home/config/umbriel/` |
| Umbriel validation or file deployment | `desktops/umbriel/home.nix` |
| Niri keybindings or layout | `home/config/niri/config.kdl` |
| Shared theme, cursor, or fonts | `modules/system/default.nix` |
| Desktop portal defaults | `modules/desktop/xdg-portal.nix` |
| System packages | `modules/system/packages.nix` |
| Steam, GameMode, or gaming graphics | `modules/others/gaming.nix` |
| Hostname, NetworkManager, VPN, DNS, or networking rules | `modules/system/network.nix` |
| Additional storage mounts | `modules/system/drives.nix` |
| File-manager services | `modules/others/file-manager.nix` |
| Virtual machines | `modules/others/virtualization.nix` |
| Nix settings, garbage collection, or firmware updates | `modules/others/maintenance.nix` |
| Locale, input method, or printing | `modules/system/locale.nix` |
| Kitty settings | `home/config/kitty/kitty.conf` |
| Shared Home Manager settings | `home/desktop-common.nix` |
| Bootloader or kernel | `modules/system/boot.nix` |
| User account or Home Manager integration | `modules/system/users.nix` |
| Shared module imports or system state version | `configuration.nix` |
| Umbriel or Xwayland Satellite package overrides | `overlays/default.nix` |

## Checking changes

Format the repository's Nix files using the formatter pinned through nixpkgs:

```bash
nix fmt
```

For CI, format all Nix files and fail if any formatting changes were needed:

```bash
nix fmt -- --ci
```

Evaluate all five desktop outputs without building or updating the lock file:

```bash
nix flake check --no-build --no-update-lock-file
```

Run evaluation and the existing Umbriel configuration validator together:

```bash
nix flake check --no-update-lock-file
```

The `checks.x86_64-linux.umbriel-config` output reuses the same validator that
Home Manager uses for the compositor configuration, including its supplemental
TOML files and an empty runtime-theme placeholder. This builds the validation
derivation and its dependencies, not the full system. To run only this check:

```bash
nix build --no-link --no-update-lock-file .#checks.x86_64-linux.umbriel-config
```

Successful validation results can be reused from the Nix store. Add `--rebuild`
to the `nix build` command to rerun an already-built validator locally.

Add `--offline` when all required inputs and build dependencies are available
locally. The `--no-build` variant checks module composition, options, and
assertions but skips running the validator. Neither check tests a live desktop
session. Build the selected output before activating it, using the commands above.

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
- Steam and Solaar are installed by their enabled NixOS modules. Steam's module supplies the package configured for the system's graphics and fonts; neither application needs an additional entry in `environment.systemPackages`.
- Noctalia Greeter uses greetd for the Umbriel and Niri outputs, with the session selected by the desktop entry point.
- The `nix-flatpak` input and module import are retained. The commented Flatpak configuration in `modules/system/packages.nix` is intentionally kept as a reference for future use; it currently enables no Flatpak service or app installation.
- `hardware-configuration.nix` is specific to this machine and should be regenerated for different hardware.
- Review the machine-specific UUIDs and ownership options in `modules/system/drives.nix` when adapting this repository to another machine.
- Do not change `system.stateVersion` or `home.stateVersion` merely when updating NixOS; they preserve compatibility with the original installation state.
