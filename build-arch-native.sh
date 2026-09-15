#!/bin/bash
set -euo pipefail

# =============================================================================
# KineticWE - Arch Linux Native Dev Build Script
# =============================================================================
# Builds KineticWE directly on the host system using pacman (no distrobox).
# Noctalia greeter is built from source (no AUR/yay dependency).
#
# Usage:
#   ./build-arch-native.sh                         # Default: binary build
#   ./build-arch-native.sh --binary                # cmake build (incremental, no package)
#   ./build-arch-native.sh --full                  # cmake build + install/activate Noctalia greeter
#   ./build-arch-native.sh --kwin-only             # Incremental kwin-only build (no portal/shell)
#   ./build-arch-native.sh --noct-only             # Incremental noctalia shell-only build
#   ./build-arch-native.sh --install-host-deps     # Implies --binary; installs missing host runtime
#                                                  # deps + default session packages
#   ./build-arch-native.sh --no-session            # Skip installing the login-screen session entry
#   ./build-arch-native.sh --reset-local           # Remove dev files from TEST_PREFIX + session entry
#   ./build-arch-native.sh --clean-deps            # Remove build-only dependencies
#
# All build modes install into TEST_PREFIX so you can test with a single command.
#
# Environment variables:
#   TEST_PREFIX     - Where to install for TTY testing (default: $HOME/.local)
#   NOCTALIA_GREETER_REPO - Git URL for noctalia-greeter (default: https://github.com/noctalia-dev/noctalia-greeter)
# =============================================================================

TEST_PREFIX="${TEST_PREFIX:-$HOME/.local}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_DIR="${SCRIPT_DIR}/lgl-kineticwe-copr"
RESULTS_DIR="${SPEC_DIR}/results"
NOCTALIA_GREETER_REPO="${NOCTALIA_GREETER_REPO:-https://github.com/noctalia-dev/noctalia-greeter}"

SESSION_DIR="/usr/local/share/wayland-sessions"
SESSION_DESKTOP="kineticwe-dev.desktop"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Parse spec metadata
# ---------------------------------------------------------------------------
SPEC_FILE="${SPEC_DIR}/kineticwe.spec"
SPEC_VERSION=$(awk '/^Version:/ {print $2; exit}' "$SPEC_FILE")
SPEC_RELEASE=$(awk '/^Release:/ {print $2; exit}' "$SPEC_FILE" | sed 's/%{?dist}//')
PACKAGE=$(awk '/^Name:/ {print $2; exit}' "$SPEC_FILE")

# Pinned KDE-source refs
SPEC_KGA_REF=$(sed -n 's/.*%global kglobalacceld_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)
SPEC_KDECO_REF=$(sed -n 's/.*%global kdecoration_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)
SPEC_AURORAE_REF=$(sed -n 's/.*%global aurorae_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)
SPEC_KCONFIG_REF=$(sed -n 's/.*%global kconfig_compiler_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)

NEXT_DEV=1
if [[ -d "$RESULTS_DIR" ]]; then
    EXISTING_DEVS=$(find "$RESULTS_DIR" -type f -name "*.pkg.tar*" -printf '%f\n' 2>/dev/null | grep -oP "\.dev\d+" | grep -oP "\d+" || true)
    if [[ -n "$EXISTING_DEVS" ]]; then
        NEXT_DEV=$(( $(echo "$EXISTING_DEVS" | sort -n | tail -1) + 1 ))
    fi
fi
DEV_RELEASE="${SPEC_RELEASE}.dev${NEXT_DEV}"

ARCH=$(uname -m)

# ---------------------------------------------------------------------------
# Build dependency lists
# ---------------------------------------------------------------------------

# Core build deps (same as kineticwe.spec BuildRequires)
BUILD_DEPS=(
    base-devel cmake ninja gcc extra-cmake-modules pkgconf meson
    curl wget git rsync
    qt6-base qt6-declarative qt6-svg qt6-5compat qt6-wayland qt6-tools
    kauth kcolorscheme kconfig kcoreaddons kcrash kdbusaddons
    kglobalaccel kio kjobwidgets kguiaddons ki18n kidletime
    kpackage kservice ksvg kwidgetsaddons kwindowsystem
    kdeclarative kcmutils knewstuff kxmlgui krunner knotifications
    kirigami kiconthemes kitemviews kstatusnotifieritem
    kwayland kscreenlocker knighttime
    plasma-wayland-protocols plasma-activities libplasma
    libepoxy wayland wayland-protocols
    libxkbcommon libxkbcommon-x11 libinput libdrm mesa
    libdisplay-info lcms2 libxcvt libcanberra libevdev
    systemd pipewire libglvnd freetype2 fontconfig
    vulkan-icd-loader vulkan-headers
    libx11 libxcb xcb-util-keysyms xcb-util-cursor xcb-util
    xcb-util-wm xcb-util-image xcb-util-renderutil
    libqaccessibilityclient-qt6 cairo pango harfbuzz glib2 pam polkit
    curl libwebp librsvg libqalculate libxml2 jemalloc
)

# Noctalia shell deps (additional)
SHELL_DEPS=(
    libsodium libsecret sdbus-cpp wireplumber libsndfile
    libjxl md4c tomlplusplus libical nlohmann-json
)

# Noctalia greeter deps (additional, for --full mode)
GREETER_DEPS=(
    wlroots0.20 libinput
)

# Default session packages: icon themes, cursor, Qt tools, Xwayland, terminal
SESSION_PKGS=(
    breeze-icons
    plasma-breeze-common
    plasma-breeze
    aurorae
    qt5ct
    qt6ct
    xorg-xwayland
    alacritty
)

# QML runtime modules the portal backend loads
PORTAL_QML_PKGS=(
    kirigami
    kitemmodels
    ki18n
    pipewire
    kiconthemes
    kcmutils
    kdeclarative
)

# QML runtime modules compositor effects load
KWIN_QML_PKGS=(
    plasma-milou
    libplasma
    qt6-5compat
)

# PipeWire media stack (screen capture + audio). The compositor's screencast
# plugin and the portal backend need a live PipeWire daemon and a session
# manager (wireplumber) to create and route the capture node. pipewire itself
# is already pulled in by PORTAL_QML_PKGS; wireplumber (session manager) and
# pipewire-pulse (audio) were only build-time deps, so add them at runtime so a
# fresh "from nothing" install screenshares out of the box.
MEDIA_RUNTIME_PKGS=(
    wireplumber
    pipewire-pulse
)

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_prereqs() {
    step "Checking prerequisites..."
    local missing=()
    for tool in cmake meson ninja git curl pacman; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    info "All prerequisites met."
    info "Package: ${PACKAGE} ${SPEC_VERSION}-${DEV_RELEASE}"
}

# ---------------------------------------------------------------------------
# Install build dependencies
# ---------------------------------------------------------------------------
install_build_deps() {
    step "Installing build dependencies..."
    sudo -v 2>/dev/null || warn "sudo not cached; you may be prompted."

    local -a all_build_deps=("${BUILD_DEPS[@]}" "${SHELL_DEPS[@]}")
    local -a missing=()
    for pkg in "${all_build_deps[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing ${#missing[@]} missing packages..."
        sudo pacman -S --noconfirm --needed "${missing[@]}"
    else
        info "All build dependencies already installed."
    fi

    # Vendor stb headers (no Arch package for stb_image_resize2/stb_image_write)
    if [[ ! -f /usr/include/stb/stb_image_resize2.h || ! -f /usr/include/stb/stb_image_write.h ]]; then
        info "Downloading stb headers..."
        sudo mkdir -p /usr/include/stb
        sudo curl -fsSL -o /usr/include/stb/stb_image_resize2.h \
            https://raw.githubusercontent.com/nothings/stb/master/stb_image_resize2.h
        sudo curl -fsSL -o /usr/include/stb/stb_image_write.h \
            https://raw.githubusercontent.com/nothings/stb/master/stb_image_write.h
    fi

    info "Build dependencies ready."
}

# ---------------------------------------------------------------------------
# Install greeter build dependencies (--full mode)
# ---------------------------------------------------------------------------
install_greeter_deps() {
    step "Installing noctalia-greeter build dependencies..."
    sudo -v 2>/dev/null || warn "sudo not cached; you may be prompted."

    local -a missing=()
    for pkg in "${GREETER_DEPS[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing ${#missing[@]} missing greeter packages..."
        sudo pacman -S --noconfirm --needed "${missing[@]}"
    else
        info "All greeter build dependencies already installed."
    fi
}

# ---------------------------------------------------------------------------
# Install host runtime dependencies
# ---------------------------------------------------------------------------
install_host_deps_arch() {
    step "Installing host runtime dependencies..."

    local -a all_pkgs=("${SESSION_PKGS[@]}" "${PORTAL_QML_PKGS[@]}" "${KWIN_QML_PKGS[@]}" "${MEDIA_RUNTIME_PKGS[@]}")
    local -a missing=()
    for pkg in "${all_pkgs[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Installing missing session/runtime packages:"
        printf '    %s\n' "${missing[@]}"
        sudo pacman -S --noconfirm --needed "${missing[@]}"
    else
        info "All session/runtime packages already installed."
    fi

    # Auto-detect missing shared libraries from the built binaries
    local -a dev_binaries=(
        "$TEST_PREFIX/bin/kinetic-we"
        "$TEST_PREFIX/bin/noctalia-kwe"
        "$TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
    )

    local -a missing_libs=()
    for binary in "${dev_binaries[@]}"; do
        [[ -x "$binary" ]] || continue
        local out
        out=$(LD_LIBRARY_PATH="${TEST_PREFIX}/lib64:${TEST_PREFIX}/lib" \
            ldd "$binary" 2>/dev/null | awk '/not found/ {print $1}' || true)
        [[ -z "$out" ]] && continue
        while IFS= read -r lib; do
            [[ -n "$lib" ]] && missing_libs+=("$lib")
        done <<< "$out"
    done

    if [[ ${#missing_libs[@]} -gt 0 ]]; then
        echo
        info "Missing runtime libraries:"
        printf '    %s\n' "${missing_libs[@]}" | sort -u

        local -a resolve_pkgs=()
        for lib in $(printf '%s\n' "${missing_libs[@]}" | sort -u); do
            local pkg_name
            pkg_name=$(pacman -F "$lib" 2>/dev/null | awk '/^.* is owned by / {print $1}' | head -1 || true)
            if [[ -n "$pkg_name" ]]; then
                info "    $lib -> $pkg_name"
                resolve_pkgs+=("$pkg_name")
            else
                warn "    $lib -> (no package found)"
            fi
        done

        if [[ ${#resolve_pkgs[@]} -gt 0 ]]; then
            sudo pacman -S --noconfirm --needed "${resolve_pkgs[@]}"
        fi
    fi

    info "Host runtime dependencies installed."
}

# ---------------------------------------------------------------------------
# Clean build-only dependencies
# ---------------------------------------------------------------------------
clean_build_deps() {
    step "Removing build-only dependencies..."

    # Packages that are only needed for building, not runtime
    local -a build_only=(
        extra-cmake-modules pkgconf
        qt6-tools
        kauth kcolorscheme kcrash kdbusaddons
        kglobalaccel kio kjobwidgets kguiaddons kidletime
        kpackage kservice ksvg kwidgetsaddons kwindowsystem
        kdeclarative kcmutils knewstuff kxmlgui krunner knotifications
        kirigami kiconthemes kitemviews kstatusnotifieritem
        kscreenlocker
        vulkan-icd-loader vulkan-headers
        xcb-util-keysyms xcb-util-cursor xcb-util
        xcb-util-wm xcb-util-image xcb-util-renderutil
        qaccessibilityclient
        libsodium libsecret sdbus-cpp libsndfile
        libjxl md4c libical
        wlroots
        jemalloc
        gcc
    )

    # Only remove packages that were installed as dependencies (not explicitly by user)
    local -a to_remove=()
    for pkg in "${build_only[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            # Check if it was installed as a dependency (not explicitly)
            local install_reason
            install_reason=$(pacman -Qi "$pkg" 2>/dev/null | awk -F': ' '/^Install Reason/ {print $2}')
            if [[ "$install_reason" == "Installed as a dependency for another package" ]]; then
                to_remove+=("$pkg")
            fi
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        info "Removing ${#to_remove[@]} build-only packages..."
        sudo pacman -Rs --noconfirm "${to_remove[@]}" || warn "Some packages could not be removed (may be needed by others)."
    else
        info "No build-only packages to remove."
    fi

    info "Clean complete."
}

# ---------------------------------------------------------------------------
# Build pinned dependencies (kglobalacceld, kdecoration, kconfig_compiler)
# ---------------------------------------------------------------------------
build_pinned_deps() {
    step "Building pinned KDE dependencies..."

    # Build kglobalacceld if not already installed
    if [[ ! -d "${TEST_PREFIX}/lib/cmake/KGlobalAccelD" ]]; then
        info "Building kglobalacceld..."
        local kga_build
        kga_build=$(mktemp -d /tmp/kga-build.XXXXXX)
        curl -fsSL "https://invent.kde.org/plasma/kglobalacceld/-/archive/${SPEC_KGA_REF}/kglobalacceld-${SPEC_KGA_REF}.tar.gz" \
            | tar xz -C "$kga_build" --strip-components=1
        cmake -B "$kga_build/build" -S "$kga_build" \
            -DCMAKE_INSTALL_PREFIX="${TEST_PREFIX}" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DBUILD_TESTING=OFF
        cmake --build "$kga_build/build" --parallel "$(nproc)"
        cmake --install "$kga_build/build"
        rm -rf "$kga_build"
    else
        info "kglobalacceld already installed."
    fi

    # Build kdecoration if not already installed
    if [[ ! -d "${TEST_PREFIX}/lib/cmake/KDecoration3" ]]; then
        info "Building kdecoration (pinned master for KDecoration3::Style)..."
        local kdeco_build
        kdeco_build=$(mktemp -d /tmp/kdeco-build.XXXXXX)
        curl -fsSL "https://invent.kde.org/plasma/kdecoration/-/archive/${SPEC_KDECO_REF}/kdecoration-${SPEC_KDECO_REF}.tar.gz" \
            | tar xz -C "$kdeco_build" --strip-components=1
        cmake -B "$kdeco_build/build" -S "$kdeco_build" \
            -DCMAKE_INSTALL_PREFIX="${TEST_PREFIX}" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DBUILD_TESTING=OFF
        cmake --build "$kdeco_build/build" --parallel "$(nproc)"
        cmake --install "$kdeco_build/build"
        rm -rf "$kdeco_build"
    else
        info "kdecoration already installed."
    fi

    # Build aurorae if not already installed (must be built against our own
    # kdecoration for ABI compatibility)
    if [[ ! -f "${TEST_PREFIX}/lib/qt6/plugins/org.kde.kdecoration3/org.kde.kwin.aurorae.v2.so" ]]; then
        info "Building aurorae (pinned master for KDecoration3 ABI compat)..."
        local aurorae_build
        aurorae_build=$(mktemp -d /tmp/aurorae-build.XXXXXX)
        curl -fsSL "https://invent.kde.org/plasma/aurorae/-/archive/${SPEC_AURORAE_REF}/aurorae-${SPEC_AURORAE_REF}.tar.gz" \
            | tar xz -C "$aurorae_build" --strip-components=1
        cmake -B "$aurorae_build/build" -S "$aurorae_build" \
            -DCMAKE_INSTALL_PREFIX="${TEST_PREFIX}" \
            -DCMAKE_PREFIX_PATH="${TEST_PREFIX}" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DBUILD_TESTING=OFF
        cmake --build "$aurorae_build/build" --parallel "$(nproc)"
        cmake --install "$aurorae_build/build"
        rm -rf "$aurorae_build"
    else
        info "aurorae already installed."
    fi

    # kconfig_compiler from KConfig < 6.30 generates uncompilable setters
    KCFG_COMPILER_OVERRIDE=""
    local kcfg_test
    kcfg_test=$(mktemp -d /tmp/kcfg-test.XXXXXX)
    /usr/libexec/kf6/kconfig_compiler_kf6 src/rulesettings.kcfg src/rulesettings.kcfgc -d "$kcfg_test" 2>/dev/null || true
    if ! grep -q 'mDecorationpolicy = int(v)' "$kcfg_test/rulesettings.h" 2>/dev/null; then
        info "System kconfig_compiler is broken (KConfig <6.30); building fixed one..."
        local kcfg_fix
        kcfg_fix=$(mktemp -d /tmp/kconfig-fix.XXXXXX)
        mkdir -p "$kcfg_fix/src"
        curl -fsSL "https://invent.kde.org/frameworks/kconfig/-/archive/${SPEC_KCONFIG_REF}/kconfig-${SPEC_KCONFIG_REF}.tar.gz" \
            | tar xz -C "$kcfg_fix/src" --strip-components=1
        cmake -B "$kcfg_fix/build" -S "$kcfg_fix/src" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_TESTING=OFF
        cmake --build "$kcfg_fix/build" --target kconfig_compiler --parallel "$(nproc)"
        KCFG_COMPILER_OVERRIDE="$kcfg_fix/build/bin/kconfig_compiler_kf6"
    fi
    rm -rf "$kcfg_test"
}

# ---------------------------------------------------------------------------
# Build KineticWE compositor, portal, and noctalia shell
# ---------------------------------------------------------------------------
binary_build() {
    local build_portal="${1:-true}"
    local build_shell="${2:-true}"
    local incremental_kwin="${3:-false}"
    local build_dir="${SCRIPT_DIR}/build.arch-native"

    step "Building KineticWE (prefix: ${TEST_PREFIX}; portal: ${build_portal}, shell: ${build_shell}, incremental: ${incremental_kwin})..."

    # Build pinned deps first
    build_pinned_deps

    # Configure KineticWE
    if [[ "$incremental_kwin" == true && -d "$build_dir" ]]; then
        info "Reusing existing KineticWE build dir (incremental)..."
    else
        info "Configuring KineticWE..."
        rm -rf "$build_dir"
        cmake -B "$build_dir" -S . \
            -DCMAKE_INSTALL_PREFIX="${TEST_PREFIX}" \
            -DCMAKE_PREFIX_PATH="${TEST_PREFIX}" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DBUILD_TESTING=OFF \
            -DKWIN_KCONFIG_COMPILER="$KCFG_COMPILER_OVERRIDE" \
            -DKWIN_BUILD_GLOBALSHORTCUTS=ON
    fi

    info "Building KineticWE..."
    cmake --build "$build_dir" --parallel "$(nproc)"

    info "Installing to ${TEST_PREFIX}..."
    cmake --install "$build_dir"

    # Build and install the KineticWE portal backend
    if [[ "$build_portal" == true ]]; then
        info "Building xdg-desktop-portal-kwe..."
        local portal_build
        portal_build=$(mktemp -d /tmp/portal-build.XXXXXX)
        cmake -B "$portal_build" -S 'portal/xdg-desktop-portal-kwe' \
            -DCMAKE_INSTALL_PREFIX="${TEST_PREFIX}" \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DBUILD_TESTING=OFF
        cmake --build "$portal_build" --parallel "$(nproc)"
        cmake --install "$portal_build"
        rm -rf "$portal_build"
    fi

    # Build and install the Noctalia fork shell
    if [[ "$build_shell" == true ]]; then
        info "Building noctalia-kwe (Noctalia fork shell)..."
        local shell_build="${SCRIPT_DIR}/build.arch-native-noctalia"
        rm -rf "$shell_build"
        meson setup "$shell_build" 'shell/noctalia' \
            --prefix="${TEST_PREFIX}" \
            --buildtype=debugoptimized \
            -Dtests=disabled
        meson compile -C "$shell_build" --jobs "$(nproc)"
        meson install -C "$shell_build"
    fi

    if [[ ! -x "$TEST_PREFIX/bin/kinetic-we" ]]; then
        error "Binary build did not produce $TEST_PREFIX/bin/kinetic-we"
        exit 1
    fi
    if [[ "$build_shell" == true ]] && [[ ! -x "$TEST_PREFIX/bin/noctalia-kwe" ]]; then
        error "Binary build did not produce $TEST_PREFIX/bin/noctalia-kwe"
        exit 1
    fi
    info "Binary build installed to $TEST_PREFIX"
}

# ---------------------------------------------------------------------------
# KWin-only build: incremental cmake build of kinetic-we (no portal/shell)
# ---------------------------------------------------------------------------
kwin_only_build() {
    binary_build false false true
}

# ---------------------------------------------------------------------------
# Noctalia-only build: incremental meson build of shell/noctalia
# ---------------------------------------------------------------------------
noctalia_only_build() {
    local shell_build="${SCRIPT_DIR}/build.arch-native-noctalia"

    step "Building noctalia-kwe only (incremental)..."

    if [[ ! -d "$shell_build" ]]; then
        info "Configuring noctalia-kwe (fresh)..."
        meson setup "$shell_build" 'shell/noctalia' \
            --prefix="${TEST_PREFIX}" \
            --buildtype=debugoptimized \
            -Dtests=disabled
    else
        info "Reusing existing noctalia-kwe build dir (incremental)..."
    fi

    info "Building noctalia-kwe..."
    meson compile -C "$shell_build" --jobs "$(nproc)"

    info "Installing to ${TEST_PREFIX}..."
    meson install -C "$shell_build"

    if [[ ! -x "$TEST_PREFIX/bin/noctalia-kwe" ]]; then
        error "Noctalia-only build did not produce $TEST_PREFIX/bin/noctalia-kwe"
        exit 1
    fi
    info "Noctalia-only build installed to $TEST_PREFIX"
}

# ---------------------------------------------------------------------------
# Verify host runtime dependencies of the installed dev binaries
# ---------------------------------------------------------------------------
verify_host_deps() {
    step "Verifying host runtime dependencies..."

    local -a binaries=(
        "$TEST_PREFIX/bin/kinetic-we"
        "$TEST_PREFIX/bin/noctalia-kwe"
        "$TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
    )

    local -a missing_libs=()
    for binary in "${binaries[@]}"; do
        [[ -x "$binary" ]] || continue
        local missing_in_binary
        missing_in_binary=$(LD_LIBRARY_PATH="${TEST_PREFIX}/lib64:${TEST_PREFIX}/lib" \
            ldd "$binary" 2>/dev/null | awk '/not found/ {print $1}' || true)
        if [[ -n "$missing_in_binary" ]]; then
            info "  $(basename "$binary") needs libraries the host does not have:"
            while IFS= read -r lib; do
                info "    $lib"
                missing_libs+=("$lib")
            done <<< "$missing_in_binary"
        fi
    done

    if [[ ${#missing_libs[@]} -eq 0 ]]; then
        info "All runtime libraries resolve on the host."
        return 0
    fi

    echo
    error "The host is missing runtime libraries needed by the dev session."
    echo
    echo "  Missing library -> providing package:"
    local -a pkgs=()
    for lib in $(printf '%s\n' "${missing_libs[@]}" | sort -u); do
        local pkg
        pkg=$(pacman -Qo "$lib" 2>/dev/null | awk '{print $5}' || true)
        if [[ -z "$pkg" ]]; then
            pkg=$(pacman -Qo "$lib" 2>/dev/null | grep 'is owned by' | awk '{print $NF}' || true)
        fi
        if [[ -n "$pkg" ]]; then
            echo "    $lib -> $pkg"
            pkgs+=("$pkg")
        else
            echo "    $lib -> (no package found; try: pacman -F $lib)"
        fi
    done
    echo
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        echo "  Install with: sudo pacman -S ${pkgs[*]}"
    fi
    echo
    warn "The build succeeded but the session will fail to start until these"
    warn "libraries are installed on the host."
    exit 1
}

# ---------------------------------------------------------------------------
# Install the single dev startup script for TTY testing
# ---------------------------------------------------------------------------
install_startup_script() {
    step "Installing dev startup script..."

    mkdir -p "$TEST_PREFIX/bin"

    if [[ ! -f "$SCRIPT_DIR/scripts/start-kineticwe.sh" ]]; then
        error "Missing template: $SCRIPT_DIR/scripts/start-kineticwe.sh"
        exit 1
    fi

    sed -e "s|@INSTALL_PREFIX@|$TEST_PREFIX|g" \
        "$SCRIPT_DIR/scripts/start-kineticwe.sh" \
        > "$TEST_PREFIX/bin/start-kineticwe"
    chmod +x "$TEST_PREFIX/bin/start-kineticwe"
    info "  $TEST_PREFIX/bin/start-kineticwe"

    mkdir -p "$TEST_PREFIX/share/kineticwe"
    install -m 0644 "$SCRIPT_DIR/scripts/kineticwe-session.target" \
        "$TEST_PREFIX/share/kineticwe/kineticwe-session.target"
    info "  $TEST_PREFIX/share/kineticwe/kineticwe-session.target"
}

# ---------------------------------------------------------------------------
# Install the "KineticWE-Dev" login-screen session entry
# ---------------------------------------------------------------------------
install_dev_session_entry() {
    step "Installing 'KineticWE-Dev' login-screen session entry..."

    local template="$SCRIPT_DIR/scripts/kineticwe-dev.desktop.in"
    if [[ ! -f "$template" ]]; then
        error "Missing template: $template"
        exit 1
    fi

    local tmp_file
    tmp_file=$(mktemp --suffix=.desktop /tmp/kineticwe-dev.XXXXXX)
    sed -e "s|@INSTALL_PREFIX@|$TEST_PREFIX|g" \
        "$template" \
        > "$tmp_file"

    if command -v desktop-file-validate &>/dev/null; then
        local validate_out
        validate_out=$(desktop-file-validate "$tmp_file" 2>&1 | grep -v 'DesktopNames' || true)
        if [[ -n "$validate_out" ]]; then
            warn "desktop-file-validate reported issues (continuing anyway):"
            warn "$validate_out"
        fi
    fi

    local target="$SESSION_DIR/$SESSION_DESKTOP"

    if [[ -f "$target" ]] && cmp -s "$tmp_file" "$target"; then
        info "  $target (already up to date)"
        rm -f "$tmp_file"
    elif sudo mkdir -p "$SESSION_DIR" \
        && sudo install -m 0644 "$tmp_file" "$target"; then
        rm -f "$tmp_file"
        info "  $target"
        info "  Select 'KineticWE-Dev' at the login screen (appears after logout)."
    else
        rm -f "$tmp_file"
        warn "Could not install the session entry (sudo declined/failed)."
        warn "The dev build still works from a TTY: start-kineticwe"
    fi

    local stale="$TEST_PREFIX/share/wayland-sessions/kineticwe.desktop"
    if [[ -f "$stale" ]]; then
        rm -f "$stale"
        info "  Removed stale user-local entry: $stale"
    fi
}

# ---------------------------------------------------------------------------
# Resolve the greetd greeter user
# ---------------------------------------------------------------------------
resolve_greeter_user() {
    local cfg="/etc/greetd/config.toml"
    local user=""
    if [[ -f "$cfg" ]]; then
        user=$(awk '
            /^\[default_session\]/  { in_block=1; next }
            /^\[/                   { in_block=0 }
            in_block && /^[[:space:]]*user[[:space:]]*=/ {
                sub(/^[[:space:]]*user[[:space:]]*=[[:space:]]*"/, "")
                sub(/".*$/, "")
                print; exit
            }
        ' "$cfg" 2>/dev/null || true)
    fi
    if [[ -z "$user" ]]; then
        if id greetd &>/dev/null; then
            user="greetd"
        else
            user="greeter"
        fi
    fi
    printf '%s\n' "$user"
}

# ---------------------------------------------------------------------------
# Install and activate the Noctalia greeter (greetd + noctalia-greeter from source)
# ---------------------------------------------------------------------------
setup_noctalia_greeter() {
    step "Setting up Noctalia greeter (greetd + noctalia-greeter from source)..."

    sudo -v 2>/dev/null || warn "sudo not cached; you may be prompted more than once."

    # Install greetd from official repos
    if ! command -v greetd &>/dev/null; then
        info "Installing greetd..."
        sudo pacman -S --noconfirm --needed greetd
    else
        info "greetd already installed."
    fi

    # Build noctalia-greeter from source
    if ! command -v noctalia-greeter-session &>/dev/null; then
        info "Building noctalia-greeter from source..."
        local greeter_src
        greeter_src=$(mktemp -d /tmp/noctalia-greeter-build.XXXXXX)
        info "Cloning ${NOCTALIA_GREETER_REPO}..."
        git clone --depth=1 "$NOCTALIA_GREETER_REPO" "$greeter_src"

        info "Configuring noctalia-greeter..."
        meson setup "$greeter_src/build" "$greeter_src" \
            --prefix=/usr/local \
            --buildtype=release
            # --buildtype=release \
            # -Dtests=disabled

        info "Building noctalia-greeter..."
        meson compile -C "$greeter_src/build" --jobs "$(nproc)"

        info "Installing noctalia-greeter to /usr/local..."
        sudo meson install -C "$greeter_src/build"
        rm -rf "$greeter_src"
    else
        info "noctalia-greeter already installed."
    fi

    local session_bin
    session_bin=$(command -v noctalia-greeter-session)
    if [[ -z "$session_bin" ]]; then
        error "noctalia-greeter-session was not found after installation."
        return 1
    fi

    local greeter_user
    greeter_user=$(resolve_greeter_user)
    info "Greeter session user: ${greeter_user}"

    if ! id "$greeter_user" &>/dev/null; then
        info "Creating greetd greeter user '${greeter_user}'..."
        sudo useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter "$greeter_user" \
            || warn "Could not create user '${greeter_user}'; the greeter may not start."
    fi

    local -a need_groups=()
    for grp in video input; do
        if getent group "$grp" &>/dev/null; then
            need_groups+=("$grp")
        else
            warn "Group '${grp}' does not exist; skipping (greeter may lack DRM/input access)."
        fi
    done
    if [[ ${#need_groups[@]} -gt 0 ]] && id "$greeter_user" &>/dev/null; then
        local user_groups
        user_groups=$(id -Gn "$greeter_user" 2>/dev/null || true)
        local -a add_groups=()
        for grp in "${need_groups[@]}"; do
            [[ " $user_groups " != *" $grp "* ]] && add_groups+=("$grp")
        done
        if [[ ${#add_groups[@]} -gt 0 ]]; then
            local group_list
            group_list=$(IFS=,; echo "${add_groups[*]}")
            info "Adding '${greeter_user}' to groups: ${add_groups[*]}"
            sudo usermod -a -G "$group_list" "$greeter_user" \
                || warn "Could not add '${greeter_user}' to ${add_groups[*]}."
        else
            info "'${greeter_user}' is already in the required groups."
        fi
    fi

    local greetd_cfg="/etc/greetd/config.toml"
    if [[ -f "$greetd_cfg" ]] && grep -q "noctalia-greeter-session" "$greetd_cfg"; then
        info "greetd already configured to use noctalia-greeter-session."
    else
        info "Configuring greetd to launch the Noctalia greeter..."
        local tmp_cfg
        tmp_cfg=$(mktemp)
        if [[ -f "$greetd_cfg" ]]; then
            cp "$greetd_cfg" "$tmp_cfg"
        else
            cat > "$tmp_cfg" <<EOF
[terminal]
vt = 1

[default_session]
command = ""
user = "${greeter_user}"
EOF
        fi

        awk -v session="$session_bin" -v guser="$greeter_user" '
            BEGIN { in_block = 0 }
            /^\[default_session\]/ { in_block = 1; print; next }
            /^\[/ { in_block = 0 }
            in_block && /^[[:space:]]*command[[:space:]]*=/ {
                print "command = \"" session "\""; next
            }
            in_block && /^[[:space:]]*user[[:space:]]*=/ {
                print "user = \"" guser "\""; next
            }
            { print }
        ' "$tmp_cfg" > "$tmp_cfg.new"

        if ! grep -q '^\[default_session\]' "$tmp_cfg.new"; then
            printf '\n[default_session]\ncommand = "%s"\nuser = "%s"\n' "$session_bin" "$greeter_user" >> "$tmp_cfg.new"
        fi

        sudo mkdir -p "$(dirname "$greetd_cfg")"
        sudo install -m 0644 "$tmp_cfg.new" "$greetd_cfg"
        rm -f "$tmp_cfg" "$tmp_cfg.new"
        info "Wrote ${greetd_cfg}: default_session -> ${session_bin}"
    fi

    local setup_script="/usr/local/share/noctalia-greeter/setup_greeter_system.sh"
    if [[ -x "$setup_script" ]]; then
        info "Running Noctalia greeter system setup..."
        sudo "$setup_script"
    else
        warn "Noctalia greeter setup script not found: $setup_script"
    fi

    if [[ "$(systemctl get-default)" != "graphical.target" ]]; then
        info "Setting default boot target to graphical.target..."
        sudo systemctl set-default graphical.target
    else
        info "Default boot target is already graphical.target."
    fi

    local current_dm
    current_dm=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
    if [[ "$current_dm" == *greetd.service* ]]; then
        info "greetd is already the active display manager."
    else
        if [[ -n "$current_dm" ]]; then
            local current_unit
            current_unit=$(basename "$current_dm")
            info "Disabling current display manager: ${current_unit}"
            sudo systemctl disable "$current_unit"
        fi
        info "Enabling greetd as the display manager..."
        sudo systemctl enable greetd.service
        echo
        info "The Noctalia greeter is configured."
        info "Log out or reboot to use it."
    fi
}

# ---------------------------------------------------------------------------
# Reset local dev install
# ---------------------------------------------------------------------------
reset_local() {
    step "Removing kineticwe dev files from ${TEST_PREFIX}..."

    local removed_any=false

    local -a known_paths=(
        "$TEST_PREFIX/bin/kinetic-we"
        "$TEST_PREFIX/bin/kwin_wayland"
        "$TEST_PREFIX/bin/kwin_wayland_wrapper"
        "$TEST_PREFIX/bin/kinetic-we_wayland"
        "$TEST_PREFIX/bin/kinetic-we_wayland_wrapper"
        "$TEST_PREFIX/bin/kwindowprop"
        "$TEST_PREFIX/bin/start-kineticwe"
        "$TEST_PREFIX/lib64/libKGlobalAccelD.so"*
        "$TEST_PREFIX/lib64/libkwin.so"*
        "$TEST_PREFIX/lib64/libkcmkwincommon.so"*
        "$TEST_PREFIX/lib/libKGlobalAccelD.so"*
        "$TEST_PREFIX/lib/libkwin.so"*
        "$TEST_PREFIX/lib/libkcmkwincommon.so"*
        "$TEST_PREFIX/lib64/libexec/kwin"*
        "$TEST_PREFIX/libexec/kwin"*
        "$TEST_PREFIX/lib64/kconf_update_bin/kwin"*
        "$TEST_PREFIX/lib64/qt6/plugins/kwin"
        "$TEST_PREFIX/lib64/qt6/plugins/plasma/kcms"
        "$TEST_PREFIX/lib64/qt6/plugins/kf6/packagestructure"
        "$TEST_PREFIX/lib64/qt6/plugins/org.kde.kdecoration3"
        "$TEST_PREFIX/lib/qt6/plugins/org.kde.kdecoration3"
        "$TEST_PREFIX/lib64/qt6/qml/org/kde/kwin"
        "$TEST_PREFIX/lib/qt6/qml/org/kde/kwin"
        "$TEST_PREFIX/share/kwin-wayland"
        "$TEST_PREFIX/share/kwin/aurorae"
        "$TEST_PREFIX/libexec/plasma-apply-aurorae"
        "$TEST_PREFIX/share/config.kcfg"
        "$TEST_PREFIX/share/kconf_update"
        "$TEST_PREFIX/share/knsrcfiles"
        "$TEST_PREFIX/share/qlogging-categories6"
        "$TEST_PREFIX/share/krunner"
        "$TEST_PREFIX/share/wayland-sessions/kineticwe.desktop"
        "$TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
        "$TEST_PREFIX/share/xdg-desktop-portal"
        "$TEST_PREFIX/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwe.service"
        "$TEST_PREFIX/share/applications/org.freedesktop.impl.portal.desktop.kwe.desktop"
        "$TEST_PREFIX/lib64/systemd/user/plasma-xdg-desktop-portal-kwe.service"
        "$TEST_PREFIX/lib64/qt6/qml/org/kde/xdgdesktopportal"
        "$TEST_PREFIX/lib/qt6/qml/org/kde/xdgdesktopportal"
        "$TEST_PREFIX/bin/noctalia-kwe"
        "$TEST_PREFIX/share/noctalia"
        "$TEST_PREFIX/share/applications/dev.noctalia.Noctalia.desktop"
        "$TEST_PREFIX/share/icons/hicolor/scalable/apps/noctalia.svg"
        "$TEST_PREFIX/share/applications/dev.kineticwe.Settings.desktop"
        "$TEST_PREFIX/share/icons/hicolor/256x256/apps/kineticwe-logo.png"
    )

    for pattern in "${known_paths[@]}"; do
        # shellcheck disable=SC2086
        for f in $pattern; do
            if [[ -e "$f" || -L "$f" ]]; then
                rm -rf "$f"
                info "  Removed: $f"
                removed_any=true
            fi
        done
    done

    find "$TEST_PREFIX/lib/.build-id" -type f -name '*.debug' 2>/dev/null \
        -exec sh -c 'readelf -n "$1" 2>/dev/null | grep -q "kineticwe\|kwin"' _ {} \; \
        -delete 2>/dev/null || true

    local session_entry="$SESSION_DIR/$SESSION_DESKTOP"
    if [[ -f "$session_entry" ]]; then
        if sudo rm -f "$session_entry"; then
            info "  Removed: $session_entry"
            removed_any=true
        else
            warn "Could not remove $session_entry (sudo declined/failed)."
        fi
    fi

    if $removed_any; then
        echo
        info "Dev files removed from $TEST_PREFIX."
    else
        info "No kineticwe dev files found in $TEST_PREFIX."
    fi
}

# ---------------------------------------------------------------------------
# Print usage info
# ---------------------------------------------------------------------------
print_usage() {
    echo
    echo "=========================================="
    echo "  Build complete! TTY Usage:"
    echo "=========================================="
    echo

    if [[ -x "$TEST_PREFIX/bin/kinetic-we" ]]; then
        echo "  ┌─────────────────────────────────────────────────────┐"
        echo "  │  DEV BUILD  (local install)                         │"
        echo "  │    TTY:          start-kineticwe                    │"
        echo "  │    Login screen: KineticWE-Dev                      │"
        echo "  └─────────────────────────────────────────────────────┘"
    else
        echo "  No dev build found at $TEST_PREFIX"
        echo "  (run ./build-arch-native.sh --binary first)"
    fi
    echo

    if [[ -f "$SESSION_DIR/$SESSION_DESKTOP" ]]; then
        info "  Login-screen entry: $SESSION_DIR/$SESSION_DESKTOP"
    else
        info "  No login-screen entry installed (skipped or sudo declined)."
    fi
    echo

    info "  Dev build release tag : ${DEV_RELEASE}"
    echo

    info "  Since TEST_PREFIX=$TEST_PREFIX is in your PATH, just type:"
    info "    start-kineticwe"
    echo

    info "Rebuild after making changes:"
    info "  ./build-arch-native.sh --binary"
    echo

    info "Full dev build with the Noctalia greeter:"
    info "  ./build-arch-native.sh --full"
    echo

    info "Iterate on a single component (fast, incremental):"
    info "  ./build-arch-native.sh --kwin-only    # kwin only"
    info "  ./build-arch-native.sh --noct-only    # noctalia shell only"
    echo

    info "Build and auto-install any missing host runtime deps:"
    info "  ./build-arch-native.sh --install-host-deps"
    echo

    info "To remove local dev files:"
    info "  ./build-arch-native.sh --reset-local"
    echo

    info "To remove build-only dependencies:"
    info "  ./build-arch-native.sh --clean-deps"
    echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local do_reset_local=false
    local do_full=false
    local do_binary=false
    local do_kwin_only=false
    local do_noct_only=false
    local do_install_host_deps=false
    local do_clean_deps=false
    local do_session=true

    for arg in "$@"; do
        case "$arg" in
            --reset-local) do_reset_local=true ;;
            --full)   do_full=true ;;
            --binary) do_binary=true ;;
            --kwin-only) do_kwin_only=true ;;
            --noct-only) do_noct_only=true ;;
            --install-host-deps) do_install_host_deps=true ;;
            --clean-deps) do_clean_deps=true ;;
            --no-session) do_session=false ;;
            --help|-h) echo "Usage: $0 [--full] [--binary] [--kwin-only] [--noct-only] [--install-host-deps] [--no-session] [--reset-local] [--clean-deps]"; exit 0 ;;
            *)         warn "Unknown option: $arg";;
        esac
    done

    if $do_install_host_deps; then
        do_binary=true
    fi

    if $do_reset_local; then
        echo "=========================================="
        echo "  KineticWE Arch - Reset Local Dev Install"
        echo "=========================================="
        echo
        reset_local
        exit 0
    fi

    if $do_clean_deps; then
        echo "=========================================="
        echo "  KineticWE Arch - Clean Build Dependencies"
        echo "=========================================="
        echo
        clean_build_deps
        exit 0
    fi

    if $do_kwin_only; then
        echo "=========================================="
        echo "  KineticWE KWin-Only Dev Build (Arch Native)"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo
        check_prereqs
        kwin_only_build
        exit 0
    fi

    if $do_noct_only; then
        echo "=========================================="
        echo "  KineticWE Noctalia-Only Dev Build (Arch Native)"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo
        check_prereqs
        noctalia_only_build
        exit 0
    fi

    if $do_full || $do_binary; then
        local mode_name
        if $do_full; then
            mode_name="Full Dev Build (binaries + Noctalia greeter)"
        else
            mode_name="Binary Dev Build (no package)"
        fi
        echo "=========================================="
        echo "  KineticWE ${mode_name} (Arch Native)"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo

        check_prereqs
        install_build_deps
        if $do_full; then
            install_greeter_deps
        fi
        binary_build
        if $do_install_host_deps; then
            install_host_deps_arch
        fi
        verify_host_deps
        install_startup_script
        if $do_session; then
            install_dev_session_entry
        fi
        if $do_full; then
            local greeter_rc
            set +e
            setup_noctalia_greeter
            greeter_rc=$?
            set -e
            if [[ $greeter_rc -ne 0 ]]; then
                warn "Noctalia greeter setup did not complete cleanly; the dev build installed."
                warn "Re-run './build-arch-native.sh --full' or configure the greeter separately."
            fi
        fi
        print_usage
        exit 0
    fi

    # Default: binary build
    echo "=========================================="
    echo "  KineticWE Dev Build (Arch Native)"
    echo "  Install prefix: ${TEST_PREFIX}"
    echo "=========================================="
    echo

    check_prereqs
    install_build_deps
    binary_build
    verify_host_deps
    install_startup_script
    if $do_session; then
        install_dev_session_entry
    fi
    print_usage
}

main "$@"
