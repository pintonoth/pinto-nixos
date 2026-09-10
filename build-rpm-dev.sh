#!/bin/bash
set -euo pipefail

# =============================================================================
# KineticWE - Dev Build & Test Script
# =============================================================================
# Builds KineticWE from local source using a Fedora distrobox and installs it
# to a local testing prefix so you can run it from a TTY immediately.
#
# Usage:
#   ./build-rpm-dev.sh                          # Default: RPM build + extract for TTY testing
#   ./build-rpm-dev.sh --binary                 # cmake build (incremental, no RPM)
#   ./build-rpm-dev.sh --full                   # cmake build + install/activate Noctalia greeter
#   ./build-rpm-dev.sh --kwin-only              # Incremental kwin-only build (no portal/shell)
#   ./build-rpm-dev.sh --noct-only              # Incremental noctalia shell-only build
#   ./build-rpm-dev.sh --install                # Same as default (alias)
#   ./build-rpm-dev.sh --reset-local            # Remove dev files from TEST_PREFIX + login entry
#   ./build-rpm-dev.sh --binary --no-session    # Skip installing the login-screen session entry
#   ./build-rpm-dev.sh --install-host-deps      # Implies --binary; after the build, install any
#                                               # missing host runtime deps the session needs,
#                                               # plus the default session packages (Breeze icon/
#                                               # cursor themes, color schemes, Qt5/Qt6 tools,
#                                               # Xwayland, portal QML modules, Alacritty) on a
#                                               # fresh host
#
# All build modes install into TEST_PREFIX so you can test with a single command.
#
# All build modes also install a "KineticWE-Dev" session entry for the login
# screen (SDDM / plasma-login-manager) into /usr/local/share/wayland-sessions,
# which display managers search while leaving the COPR stable install in /usr
# untouched. The entry just points at $TEST_PREFIX/bin/start-kineticwe, so TTY
# testing is unchanged.
#
# Environment variables:
#   TEST_PREFIX     - Where to install for TTY testing (default: $HOME/.local)
#   DISTROBOX_NAME  - Name of the distrobox container (default: kineticwe-build)
#
# On Debian/Ubuntu-based hosts use build-deb-dev.sh instead: it mirrors this
# flow but builds inside a debian:sid distrobox via apt and can emit .deb
# packages (--deb).
# =============================================================================

TEST_PREFIX="${TEST_PREFIX:-$HOME/.local}"
DISTROBOX_NAME="${DISTROBOX_NAME:-kineticwe-build}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_DIR="${SCRIPT_DIR}/lgl-kineticwe-copr"
RESULTS_DIR="${SPEC_DIR}/results"
DISTROBOX_IMAGE="fedora:44"

# Login-screen session entry for the dev build. /usr/local/share is in the
# default session search path of SDDM / plasma-login-manager, so the entry
# survives deployments without touching the COPR-managed /usr.
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

# Pinned KDE-source refs — the spec is the single source of truth. The binary
# build downloads these exact commits instead of cloning KDE master, whose
# ECM/KF6 requirements drift ahead of the Fedora container (KConfig master
# now requires ECM 6.29.0 while Fedora 44 ships ECM 6.28.0).
SPEC_KGA_REF=$(sed -n 's/.*%global kglobalacceld_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)
SPEC_KDECO_REF=$(sed -n 's/.*%global kdecoration_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)
SPEC_KCONFIG_REF=$(sed -n 's/.*%global kconfig_compiler_ref \([0-9a-f]\{40\}\).*/\1/p' "$SPEC_FILE" | head -1)

NEXT_DEV=1
if [[ -d "$RESULTS_DIR" ]]; then
    EXISTING_DEVS=$(find "$RESULTS_DIR" -type f -name "*.rpm" -printf '%f\n' 2>/dev/null | grep -oP "\.dev\d+" | grep -oP "\d+" || true)
    if [[ -n "$EXISTING_DEVS" ]]; then
        NEXT_DEV=$(( $(echo "$EXISTING_DEVS" | sort -n | tail -1) + 1 ))
    fi
fi
DEV_RELEASE="${SPEC_RELEASE}.dev${NEXT_DEV}"

ARCH=$(uname -m)

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_prereqs() {
    step "Checking prerequisites..."
    if ! command -v distrobox &>/dev/null; then
        error "distrobox is required but not found."
        exit 1
    fi
    if ! command -v podman &>/dev/null && ! command -v docker &>/dev/null; then
        error "podman or docker is required but not found."
        exit 1
    fi
    if [[ ! -f "$SPEC_FILE" ]]; then
        error "Could not find spec file: $SPEC_FILE"
        exit 1
    fi
    info "All prerequisites met."
    info "Package: ${PACKAGE} ${SPEC_VERSION}-${DEV_RELEASE}"
}

# ---------------------------------------------------------------------------
# Distrobox management
# ---------------------------------------------------------------------------
setup_distrobox() {
    step "Setting up distrobox container '${DISTROBOX_NAME}'..."
    # distrobox list prints "ID | NAME | STATUS | IMAGE", so the name is
    # never at line start — match it as a word anywhere in the line.
    # No grep -q: it exits on first match, distrobox list dies with SIGPIPE,
    # and pipefail then reports the pipeline as failed even when it matched.
    if distrobox list 2>/dev/null | grep -w "$DISTROBOX_NAME" > /dev/null; then
        info "Container '${DISTROBOX_NAME}' already exists."
    else
        info "Creating distrobox from ${DISTROBOX_IMAGE}..."
        distrobox create \
            --name "$DISTROBOX_NAME" \
            --image "$DISTROBOX_IMAGE" \
            --additional-flags "--userns=keep-id" \
            --yes
        info "Container created."
    fi

    step "Ensuring build tools are installed inside the container..."
    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        if ! rpm -q rpm-build &>/dev/null; then
            # Ignore scriptlet failures (systemd/udev scripts fail in containers)
            sudo dnf install -y rpm-build rpmdevtools dnf-plugins-core curl wget git || true
            if ! rpm -q rpm-build &>/dev/null; then
                echo 'ERROR: rpm-build failed to install' >&2
                exit 1
            fi
        fi
    "

    local buildreqs
    buildreqs=$(grep '^BuildRequires:' "$SPEC_FILE" | sed 's/BuildRequires:\s*//' | tr '\n' ' ')
    info "Installing build dependencies (one-time, cached across builds)..."
    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        # Ignore scriptlet failures; container cannot run systemd/udev scripts
        sudo dnf install -y --skip-unavailable $buildreqs || true

        # Fail fast if key build tools are missing instead of dying mid-build
        missing_tools=()
        for tool in cmake meson ninja; do
            command -v \$tool &>/dev/null || missing_tools+=(\$tool)
        done
        if [[ \${#missing_tools[@]} -gt 0 ]]; then
            echo 'ERROR: build tools missing:' >&2
            printf '  %s\n' \"\${missing_tools[@]}\" >&2
            exit 1
        fi

        # Spot-check pkg-config modules for the main dep groups:
        # Qt6 (qt6-qtbase-devel), portal (pipewire-devel / wireplumber-devel),
        # noctalia (sdbus-cpp-devel)
        missing_mods=()
        for mod in Qt6Core libpipewire-0.3 wireplumber-0.5 sdbus-c++; do
            pkg-config --exists \$mod 2>/dev/null || missing_mods+=(\$mod)
        done
        if [[ \${#missing_mods[@]} -gt 0 ]]; then
            echo 'ERROR: pkg-config modules missing:' >&2
            printf '  %s\n' \"\${missing_mods[@]}\" >&2
            exit 1
        fi

        # KF6 ships CMake config files, not pkg-config .pc files, so verify
        # the kf6-kconfig-devel package directly (and its CMake config).
        if ! rpm -q kf6-kconfig-devel &>/dev/null \
            || ! ls /usr/lib64/cmake/KF6Config/KF6ConfigConfig.cmake &>/dev/null; then
            echo 'ERROR: KF6 (kf6-kconfig-devel) not installed' >&2
            exit 1
        fi
    "
    info "Build environment ready."
}

# ---------------------------------------------------------------------------
# Verify the dev distrobox container exists (lightweight, for --*-only modes)
# ---------------------------------------------------------------------------
ensure_distrobox() {
    if ! distrobox list 2>/dev/null | grep -w "$DISTROBOX_NAME" > /dev/null; then
        error "Distrobox container '${DISTROBOX_NAME}' not found."
        error "Run './build-rpm-dev.sh --binary' (or --full) once to create it."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Build RPMs inside the distrobox
# ---------------------------------------------------------------------------
build_rpms() {
    step "Building RPMs inside distrobox (Release: ${DEV_RELEASE})..."
    mkdir -p "$RESULTS_DIR"

    # Generate SRPM (which also prepares all source files)
    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        set -euo pipefail
        cd '$SCRIPT_DIR'
        make -f '${SPEC_DIR}/Makefile' srpm
        echo 'SRPM and sources ready.'
    "

    local srpm_file
    srpm_file=$(ls -1t "$RESULTS_DIR"/*.src.rpm 2>/dev/null | head -1)
    if [[ -z "$srpm_file" ]]; then
        error "No SRPM was generated!"
        exit 1
    fi
    info "SRPM: $(basename "$srpm_file")"

    # Rebuild SRPM into binary RPMs
    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        set -euo pipefail
        # rpmbuild --rebuild places binary RPMs in arch subdirectories (e.g. x86_64/),
        # so we need to remove from any level
        find '${RESULTS_DIR}' -type f -name '${PACKAGE}*.rpm' ! -name '*.src.rpm' -delete
        rpmbuild --rebuild \
            --define '_rpmdir ${RESULTS_DIR}' \
            --define 'dist .fc44' \
            '${srpm_file}'
    "

    # Rename RPMs to include dev release suffix
    local rpm_count=0
    while IFS= read -r -d '' rpm_file; do
        local base
        base=$(basename "$rpm_file")
        if [[ "$base" == *".src.rpm" ]]; then
            continue
        fi
        local escaped_release
        escaped_release=$(printf '%s\n' "$SPEC_RELEASE" | sed 's/\./\\./g')
        local new_name
        new_name=$(echo "$base" | sed "s/${escaped_release}\.fc44/${DEV_RELEASE}.fc44/")
        if [[ "$base" != "$new_name" && -n "$new_name" ]]; then
            mv "$rpm_file" "$RESULTS_DIR/$new_name"
            info "Renamed: $base -> $new_name"
        fi
        rpm_count=$((rpm_count + 1))
    done < <(find "$RESULTS_DIR" -type f -name "${PACKAGE}*.rpm" ! -name "*.src.rpm" -print0)

    if [[ "$rpm_count" -eq 0 ]]; then
        error "No binary RPMs were produced!"
        exit 1
    fi

    echo
    info "Binary RPMs produced:"
    find "$RESULTS_DIR" -type f -name "${PACKAGE}*.rpm" ! -name "*.src.rpm" -exec ls -lh {} \;
    echo
}

# ---------------------------------------------------------------------------
# Binary build: cmake directly inside the distrobox (no RPM)
# ---------------------------------------------------------------------------
binary_build() {
    local build_portal="${1:-true}"
    local build_shell="${2:-true}"
    local incremental_kwin="${3:-false}"
    local build_dir="${SCRIPT_DIR}/build.rpm-quick"

    step "Building KineticWE in distrobox (prefix: ${TEST_PREFIX}; portal: ${build_portal}, shell: ${build_shell}, incremental: ${incremental_kwin})..."

    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        set -euo pipefail

        # Strip Nix from the environment so cmake doesn't link against
        # Nix-store libraries (openssl, curl, etc.) that won't exist on
        # the host at runtime.
        unset NIX_REMOTE
        unset NIX_PATH
        unset NIX_SSL_CERT_FILE
        unset NIX_PROFILE
        unset LD_LIBRARY_PATH
        unset XDG_DATA_DIRS
        unset PKG_CONFIG_PATH
        export PATH='/usr/local/bin:/usr/bin:/bin'

        cd '$SCRIPT_DIR'

        # Build kglobalacceld if not already installed. Pinned to the spec's
        # kglobalacceld_ref: a floating master clone is not reproducible and
        # breaks when master starts requiring a newer ECM/KF6 than the
        # container provides. A local build installs its CMake config as
        # KGlobalAccelDConfig.cmake (no pkg-config file), so probe for that
        # instead of pkg-config, which would never match.
        if [[ ! -d '${TEST_PREFIX}/lib64/cmake/KGlobalAccelD' \
              && ! -d '${TEST_PREFIX}/lib/cmake/KGlobalAccelD' ]]; then
            echo '[STEP] Building kglobalacceld first...'
            KGA_BUILD=\$(mktemp -d /tmp/kga-build.XXXXXX)
            curl -fsSL https://invent.kde.org/plasma/kglobalacceld/-/archive/${SPEC_KGA_REF}/kglobalacceld-${SPEC_KGA_REF}.tar.gz \
                | tar xz -C \"\$KGA_BUILD\" --strip-components=1
            cd \"\$KGA_BUILD\"
            cmake -B build -S . \\
                -DCMAKE_INSTALL_PREFIX='${TEST_PREFIX}' \\
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
                -DBUILD_TESTING=OFF
            cmake --build build --parallel \$(nproc)
            cmake --install build
            cd '$SCRIPT_DIR'
            rm -rf \"\$KGA_BUILD\"
        fi

        # Build kdecoration if not already installed. Pinned to the spec's
        # kdecoration_ref: kinetic-we uses KDecoration3::Style (server-side
        # drop shadows for CSD windows), which does not exist in the
        # container's released kdecoration 6.7.x. Install it into TEST_PREFIX
        # so the kinetic-we configure below picks it up via CMAKE_PREFIX_PATH.
        if [[ ! -d '${TEST_PREFIX}/lib64/cmake/KDecoration3' \
              && ! -d '${TEST_PREFIX}/lib/cmake/KDecoration3' ]]; then
            echo '[STEP] Building kdecoration (pinned master for KDecoration3::Style)...'
            KDECO_BUILD=\$(mktemp -d /tmp/kdeco-build.XXXXXX)
            curl -fsSL https://invent.kde.org/plasma/kdecoration/-/archive/${SPEC_KDECO_REF}/kdecoration-${SPEC_KDECO_REF}.tar.gz \
                | tar xz -C \"\$KDECO_BUILD\" --strip-components=1
            cmake -B \"\$KDECO_BUILD/build\" -S \"\$KDECO_BUILD\" \\
                -DCMAKE_INSTALL_PREFIX='${TEST_PREFIX}' \\
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
                -DBUILD_TESTING=OFF
            cmake --build \"\$KDECO_BUILD/build\" --parallel \$(nproc)
            cmake --install \"\$KDECO_BUILD/build\"
            rm -rf \"\$KDECO_BUILD\"
        fi

        # kconfig_compiler from KConfig < 6.30 generates uncompilable setters
        # for enum-class kcfg entries (fixed in KConfig commit 41592cc, first
        # released in 6.30). Fedora 44 ships 6.28, so build a fixed compiler
        # if the system one is affected. Drop this once the container's KConfig
        # is >= 6.30.
        KCFG_COMPILER_OVERRIDE=""
        KCFG_TEST=\$(mktemp -d /tmp/kcfg-test.XXXXXX)
        /usr/libexec/kf6/kconfig_compiler_kf6 src/rulesettings.kcfg src/rulesettings.kcfgc -d "\$KCFG_TEST" 2>/dev/null || true
        if ! grep -q 'mDecorationpolicy = int(v)' "\$KCFG_TEST/rulesettings.h" 2>/dev/null; then
            echo '[STEP] System kconfig_compiler is broken (KConfig <6.30); building fixed one...'
            KCFG_FIX=\$(mktemp -d /tmp/kconfig-fix.XXXXXX)
            # Pinned to the spec's kconfig_compiler_ref: the commit with the
            # enum-class setter fix. KConfig master now requires ECM 6.29.0,
            # newer than the container's ECM 6.28.0 — hence no master clone.
            mkdir -p \"\$KCFG_FIX/src\"
            curl -fsSL https://invent.kde.org/frameworks/kconfig/-/archive/${SPEC_KCONFIG_REF}/kconfig-${SPEC_KCONFIG_REF}.tar.gz \
                | tar xz -C \"\$KCFG_FIX/src\" --strip-components=1
            cmake -B "\$KCFG_FIX/build" -S "\$KCFG_FIX/src" \\
                -DCMAKE_BUILD_TYPE=Release \\
                -DBUILD_TESTING=OFF
            cmake --build "\$KCFG_FIX/build" --target kconfig_compiler --parallel \$(nproc)
            KCFG_COMPILER_OVERRIDE="\$KCFG_FIX/build/bin/kconfig_compiler_kf6"
        fi
        rm -rf "\$KCFG_TEST"

        if [[ '$incremental_kwin' == true && -d '$build_dir' ]]; then
            echo '[STEP] Reusing existing KineticWE build dir (incremental)...'
        else
            echo '[STEP] Configuring KineticWE (fresh build dir)...'
            rm -rf '$build_dir'
        fi
        # Always (re)configure. On incremental builds this keeps the existing
        # build dir but refreshes -DKWIN_KCONFIG_COMPILER to the fixed compiler
        # built this run. Otherwise the cached value points at a stale
        # /tmp/kconfig-fix.* temp dir from an earlier run that no longer exists
        # (the fix is rebuilt under a fresh random suffix each run), which is
        # what caused the 'No rule to make target' failure.
        echo '[STEP] Configuring KineticWE...'
        cmake -B '$build_dir' -S . \\
            -DCMAKE_INSTALL_PREFIX='${TEST_PREFIX}' \\
            -DCMAKE_PREFIX_PATH='${TEST_PREFIX}' \\
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
            -DBUILD_TESTING=OFF \\
            -DKWIN_KCONFIG_COMPILER=\$KCFG_COMPILER_OVERRIDE \\
            -DKWIN_BUILD_GLOBALSHORTCUTS=ON

        echo '[STEP] Building KineticWE...'
        cmake --build '$build_dir' --parallel \$(nproc)

        echo '[STEP] Installing to ${TEST_PREFIX}...'
        cmake --install '$build_dir'

        # --- Phase 4: Build and install the KineticWE portal backend
        # (rebranded xdg-desktop-portal-kde) into the same prefix. Requires
        # kf6-kiconthemes/kf6-kitemviews/kf6-kstatusnotifieritem/kf6-kio-filewidgets
        # devel packages in the distrobox (install them via the spec's
        # BuildRequires).
        if [[ '$build_portal' == true ]]; then
            echo '[STEP] Building xdg-desktop-portal-kwe...'
            PORTAL_BUILD=\$(mktemp -d /tmp/portal-build.XXXXXX)
            cmake -B \"\$PORTAL_BUILD\" -S 'portal/xdg-desktop-portal-kwe' \\
                -DCMAKE_INSTALL_PREFIX='${TEST_PREFIX}' \\
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
                -DBUILD_TESTING=OFF
            cmake --build \"\$PORTAL_BUILD\" --parallel \$(nproc)
            cmake --install \"\$PORTAL_BUILD\"
            rm -rf \"\$PORTAL_BUILD\"
        fi

        # --- Phase 5: Build and install the Noctalia fork shell (noctalia-kwe)
        # (vendored at shell/noctalia) into the same prefix. The binary is
        # renamed to noctalia-kwe so the upstream noctalia package can coexist.
        if [[ '$build_shell' == true ]]; then
            echo '[STEP] Building noctalia-kwe (Noctalia fork shell)...'
            SHELL_BUILD='${SCRIPT_DIR}/build.rpm-quick-noctalia'
            rm -rf \"\$SHELL_BUILD\"
            meson setup \"\$SHELL_BUILD\" 'shell/noctalia' \\
                --prefix='${TEST_PREFIX}' \\
                --buildtype=debugoptimized \\
                -Dtests=disabled
            meson compile -C \"\$SHELL_BUILD\" --jobs \$(nproc)
            meson install -C \"\$SHELL_BUILD\"
        fi
    "

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
    local shell_build="${SCRIPT_DIR}/build.rpm-quick-noctalia"

    step "Building noctalia-kwe only (incremental)..."

    distrobox enter "$DISTROBOX_NAME" -- bash -c "
        set -euo pipefail

        unset NIX_REMOTE
        unset NIX_PATH
        unset NIX_SSL_CERT_FILE
        unset NIX_PROFILE
        unset LD_LIBRARY_PATH
        unset XDG_DATA_DIRS
        unset PKG_CONFIG_PATH
        export PATH='/usr/local/bin:/usr/bin:/bin'

        cd '$SCRIPT_DIR'

        if [[ ! -d '$shell_build' ]]; then
            echo '[STEP] Configuring noctalia-kwe (fresh)...'
            meson setup '$shell_build' 'shell/noctalia' \\
                --prefix='${TEST_PREFIX}' \\
                --buildtype=debugoptimized \\
                -Dtests=disabled
        else
            echo '[STEP] Reusing existing noctalia-kwe build dir (incremental)...'
        fi

        echo '[STEP] Building noctalia-kwe...'
        meson compile -C '$shell_build' --jobs \$(nproc)

        echo '[STEP] Installing to ${TEST_PREFIX}...'
        meson install -C '$shell_build'
    "

    if [[ ! -x "$TEST_PREFIX/bin/noctalia-kwe" ]]; then
        error "Noctalia-only build did not produce $TEST_PREFIX/bin/noctalia-kwe"
        exit 1
    fi
    info "Noctalia-only build installed to $TEST_PREFIX"
}

# ---------------------------------------------------------------------------
# Verify host runtime dependencies of the installed dev binaries
# ---------------------------------------------------------------------------
# The dev flow installs into TEST_PREFIX without RPM dependency resolution, so
# a binary can link a library the host does not ship and only fail at login
# with a cryptic loader error. ldd the installed binaries with the same
# LD_LIBRARY_PATH the session launcher uses and fail fast, listing the missing
# libraries and the packages that provide them.
verify_host_deps() {
    step "Verifying host runtime dependencies..."

    local -a binaries=(
        "$TEST_PREFIX/bin/kinetic-we"
        "$TEST_PREFIX/bin/noctalia-kwe"
        "$TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
    )

    local -a missing_libs=()
    local binary
    for binary in "${binaries[@]}"; do
        [[ -x "$binary" ]] || continue
        local missing_in_binary
        missing_in_binary=$(LD_LIBRARY_PATH="${TEST_PREFIX}/lib64:${TEST_PREFIX}/lib/x86_64-linux-gnu" \
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
    local lib
    for lib in $(printf '%s\n' "${missing_libs[@]}" | sort -u); do
        local pkg
        pkg=$(dnf repoquery --whatprovides "$lib" --queryformat '%{name}' 2>/dev/null | sort -u | head -1)
        if [[ -n "$pkg" ]]; then
            echo "    $lib -> $pkg"
            pkgs+=("$pkg")
        else
            echo "    $lib -> (no package found; try: dnf repoquery --whatprovides $lib)"
        fi
    done
    echo
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        echo "  Install with: sudo dnf install ${pkgs[*]}"
    fi
    echo
    warn "The build succeeded but the session will fail to start until these"
    warn "libraries are installed on the host."
    exit 1
}

# ---------------------------------------------------------------------------
# Extract RPM contents to TEST_PREFIX for TTY testing
# ---------------------------------------------------------------------------
extract_for_testing() {
    step "Extracting RPM contents to ${TEST_PREFIX} for TTY testing..."
    local rpm_file
    rpm_file=$(find "$RESULTS_DIR" -type f -name "${PACKAGE}-[0-9]*.rpm" \
        ! -name '*.src.rpm' \
        ! -name '*kglobalacceld*' \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | awk '{print $2}')
    if [[ -z "$rpm_file" ]]; then
        error "No binary RPM found to extract."
        exit 1
    fi

    # Extract to temp dir, then rsync to TEST_PREFIX stripping the usr/ prefix
    local tmpdir
    tmpdir=$(mktemp -d /tmp/kineticwe-rpm-extract.XXXXXX)
    rpm2cpio "$rpm_file" | cpio -idm -D "$tmpdir" 2>/dev/null

    # The xdg-desktop-portal-kwe subpackage is a separate RPM; extract it into
    # the same prefix so the session's portal frontend finds the backend
    # (kwe.portal + kineticwe-portals.conf land under $TEST_PREFIX/share, which
    # start-kineticwe.sh adds to XDG_DATA_DIRS).
    local portal_rpm
    portal_rpm=$(find "$RESULTS_DIR" -type f -name "xdg-desktop-portal-kwe-*.rpm" \
        ! -name '*.src.rpm' \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | awk '{print $2}')
    if [[ -n "$portal_rpm" ]]; then
        rpm2cpio "$portal_rpm" | cpio -idm -D "$tmpdir" 2>/dev/null
        info "  Portal backend: $TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
    else
        warn "No xdg-desktop-portal-kwe RPM found; the session will run without a portal backend."
    fi

    # The kineticwe-noctalia subpackage is a separate RPM; extract it into the
    # same prefix so the session's start script finds the noctalia-kwe shell
    # binary (it lands in $TEST_PREFIX/bin, already first in the session PATH).
    local shell_rpm
    shell_rpm=$(find "$RESULTS_DIR" -type f -name "kineticwe-noctalia-*.rpm" \
        ! -name '*.src.rpm' \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | awk '{print $2}')
    if [[ -n "$shell_rpm" ]]; then
        rpm2cpio "$shell_rpm" | cpio -idm -D "$tmpdir" 2>/dev/null
        info "  Shell: $TEST_PREFIX/bin/noctalia-kwe"
    else
        warn "No kineticwe-noctalia RPM found; the session will run without the shell."
    fi

    if [[ ! -x "$tmpdir/usr/bin/kinetic-we" ]]; then
        warn "Extraction produced no kinetic-we binary at expected path."
    fi

    # rsync strips usr/ so files land directly in TEST_PREFIX
    rsync -a "$tmpdir/usr/" "$TEST_PREFIX/"
    rm -rf "$tmpdir"

    info "Extracted to $TEST_PREFIX"
    info "  Binary: $TEST_PREFIX/bin/kinetic-we"
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

    # Generate the startup script from the template.
    # INSTALL_PREFIX points directly at TEST_PREFIX (no usr/ subdirectory).
    # Both binary and RPM modes produce the same flat layout now.
    sed -e "s|@INSTALL_PREFIX@|$TEST_PREFIX|g" \
        "$SCRIPT_DIR/scripts/start-kineticwe.sh" \
        > "$TEST_PREFIX/bin/start-kineticwe"
    chmod +x "$TEST_PREFIX/bin/start-kineticwe"
    info "  $TEST_PREFIX/bin/start-kineticwe"

    # The 2.0 session target (pulls graphical-session.target up for the
    # portal frontend). The launcher installs it into the user unit dir on
    # first start; this keeps packaged and dev flows identical.
    mkdir -p "$TEST_PREFIX/share/kineticwe"
    install -m 0644 "$SCRIPT_DIR/scripts/kineticwe-session.target" \
        "$TEST_PREFIX/share/kineticwe/kineticwe-session.target"
    info "  $TEST_PREFIX/share/kineticwe/kineticwe-session.target"
}

# ---------------------------------------------------------------------------
# Install the "KineticWE-Dev" login-screen session entry
# ---------------------------------------------------------------------------
# Display managers (SDDM / plasma-login-manager) only scan system session
# dirs — never ~/.local/share/wayland-sessions — so the entry must live in
# SESSION_DIR (see above). The entry's Exec points at the same launcher used
# for TTY testing, so both login paths run identical code.
#
# One-time sudo: skipped on later runs while the installed file is identical.
install_dev_session_entry() {
    step "Installing 'KineticWE-Dev' login-screen session entry..."

    local template="$SCRIPT_DIR/scripts/kineticwe-dev.desktop.in"
    if [[ ! -f "$template" ]]; then
        error "Missing template: $template"
        exit 1
    fi

    local tmp_file
    # .desktop suffix: desktop-file-validate rejects files without it.
    tmp_file=$(mktemp --suffix=.desktop /tmp/kineticwe-dev.XXXXXX)
    sed -e "s|@INSTALL_PREFIX@|$TEST_PREFIX|g" \
        "$template" \
        > "$tmp_file"

    # Sanity-check the generated file. DesktopNames is a valid key for
    # session files (desktop entry spec 1.5) but desktop-file-validate still
    # flags it — even Fedora's shipped plasma.desktop "fails" on it — so
    # ignore that specific false positive and only warn about real issues.
    if command -v desktop-file-validate &>/dev/null; then
        local validate_out
        validate_out=$(desktop-file-validate "$tmp_file" 2>&1 | grep -v 'DesktopNames' || true)
        if [[ -n "$validate_out" ]]; then
            warn "desktop-file-validate reported issues (continuing anyway):"
            warn "$validate_out"
        fi
    fi

    local target="$SESSION_DIR/$SESSION_DESKTOP"

    # Skip sudo entirely when the installed entry is already up to date.
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
        warn "To install the login entry manually:"
        warn "  sudo install -m 0644 $template $target   # after sed substitution"
    fi

    # Remove the stale user-local session entry: it has the same Name= as the
    # COPR stable entry but Exec points at the dev build, and no display
    # manager ever scans ~/.local/share/wayland-sessions — pure clutter.
    # RPM mode re-extracts it on every build, so this runs every time.
    local stale="$TEST_PREFIX/share/wayland-sessions/kineticwe.desktop"
    if [[ -f "$stale" ]]; then
        rm -f "$stale"
        info "  Removed stale user-local entry: $stale"
    fi
}

# ---------------------------------------------------------------------------
# Resolve the user greetd actually runs the greeter session as. Reads the
# `user = "..."` line from [default_session] in /etc/greetd/config.toml; falls
# back to the greetd package user, then the conventional 'greeter' user. The
# script previously hardcoded 'greeter', which mismatched a config running as
# 'greetd' and errored on usermod, aborting the whole --full build.
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
# Install and activate the Noctalia greeter (greetd + noctalia-greeter-git)
# ---------------------------------------------------------------------------
setup_noctalia_greeter() {
    step "Setting up Noctalia greeter (lionheartp/Hyprland COPR)..."

    # Refresh/cache sudo credentials up front so the many systemctl/dnf calls
    # below need only a single password entry. Failure here is non-fatal.
    sudo -v 2>/dev/null || warn "sudo not cached; you may be prompted more than once."

    # The greeter runs under greetd and is packaged in the LionHeartP COPR.
    local copr_repo="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:lionheartp:Hyprland.repo"
    if [[ ! -f "$copr_repo" ]]; then
        info "Enabling lionheartp/Hyprland COPR..."
        sudo dnf -y copr enable lionheartp/Hyprland
    else
        info "lionheartp/Hyprland COPR already enabled."
    fi

    if ! command -v noctalia-greeter-session &>/dev/null || ! command -v greetd &>/dev/null; then
        info "Installing noctalia-greeter-git and greetd..."
        sudo dnf install -y noctalia-greeter-git greetd
    else
        info "noctalia-greeter and greetd already installed."
    fi

    local session_bin
    session_bin=$(command -v noctalia-greeter-session)
    if [[ -z "$session_bin" ]]; then
        error "noctalia-greeter-session was not found after installation."
        return 1
    fi

    # Resolve the user greetd actually runs the greeter as ('greetd' on this
    # host), then ensure that user exists and has DRM/input access. Idempotent
    # and guarded so a failure warns instead of aborting the already-built full
    # install.
    local greeter_user
    greeter_user=$(resolve_greeter_user)
    info "Greeter session user: ${greeter_user}"

    if ! id "$greeter_user" &>/dev/null; then
        info "Creating greetd greeter user '${greeter_user}'..."
        sudo useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter "$greeter_user" \
            || warn "Could not create user '${greeter_user}'; the greeter may not start."
    fi

    # Grant DRM/input access only if the groups exist and the user is not
    # already a member. Never fail the one-shot because a group is absent.
    local -a need_groups=()
    local grp
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

    # Point greetd at the packaged session wrapper unless it already is.
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

        # Replace the command/user lines inside [default_session], or append
        # the block when the file has none.
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

    # Run the packaged system setup: PAM patch, state dir, greeter.toml.
    local setup_script="/usr/share/noctalia-greeter/setup_greeter_system.sh"
    if [[ -x "$setup_script" ]]; then
        info "Running Noctalia greeter system setup..."
        sudo "$setup_script"
    else
        warn "Noctalia greeter setup script not found: $setup_script"
    fi

    # Boot into the graphical target so the display manager starts at boot.
    if [[ "$(systemctl get-default)" != "graphical.target" ]]; then
        info "Setting default boot target to graphical.target..."
        sudo systemctl set-default graphical.target
    else
        info "Default boot target is already graphical.target."
    fi

    # Make greetd the active login greeter unless it already is.
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
# Reset local dev install (remove kineticwe files from TEST_PREFIX)
# ---------------------------------------------------------------------------
reset_local() {
    step "Removing kineticwe dev files from ${TEST_PREFIX}..."

    local removed_any=false

    # Remove files known to be installed by the kineticwe package.
    # This follows the %files section of the spec — only targets paths
    # within TEST_PREFIX that kineticwe owns.
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
        "$TEST_PREFIX/lib64/libexec/kwin"*
        "$TEST_PREFIX/lib64/kconf_update_bin/kwin"*
        "$TEST_PREFIX/lib64/qt6/plugins/kwin"
        "$TEST_PREFIX/lib64/qt6/plugins/plasma/kcms"
        "$TEST_PREFIX/lib64/qt6/plugins/kf6/packagestructure"
        "$TEST_PREFIX/lib64/qt6/qml/org/kde/kwin"
        "$TEST_PREFIX/share/kwin-wayland"
        "$TEST_PREFIX/share/config.kcfg"
        "$TEST_PREFIX/share/kconf_update"
        "$TEST_PREFIX/share/knsrcfiles"
        "$TEST_PREFIX/share/qlogging-categories6"
        "$TEST_PREFIX/share/krunner"
        "$TEST_PREFIX/share/wayland-sessions/kineticwe.desktop"
        # xdg-desktop-portal-kwe (portal backend subpackage)
        "$TEST_PREFIX/libexec/xdg-desktop-portal-kwe"
        "$TEST_PREFIX/share/xdg-desktop-portal"
        "$TEST_PREFIX/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwe.service"
        "$TEST_PREFIX/share/applications/org.freedesktop.impl.portal.desktop.kwe.desktop"
        "$TEST_PREFIX/lib64/systemd/user/plasma-xdg-desktop-portal-kwe.service"
        "$TEST_PREFIX/lib64/qt6/qml/org/kde/xdgdesktopportal"
        "$TEST_PREFIX/lib/qt6/qml/org/kde/xdgdesktopportal"
        # kineticwe-noctalia (Noctalia fork shell, noctalia-kwe)
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

    # Also remove .build-id entries that belong to kineticwe
    find "$TEST_PREFIX/lib/.build-id" -type f -name '*.debug' 2>/dev/null \
        -exec sh -c 'readelf -n "$1" 2>/dev/null | grep -q "kineticwe\|kwin"' _ {} \; \
        -delete 2>/dev/null || true

    # Remove the login-screen session entry (lives outside TEST_PREFIX).
    local session_entry="$SESSION_DIR/$SESSION_DESKTOP"
    if [[ -f "$session_entry" ]]; then
        if sudo rm -f "$session_entry"; then
            info "  Removed: $session_entry"
            removed_any=true
        else
            warn "Could not remove $session_entry (sudo declined/failed)."
            warn "Remove it manually: sudo rm -f $session_entry"
        fi
    fi

    if $removed_any; then
        echo
        info "Dev files removed from $TEST_PREFIX."
        info "The COPR stable install in /usr/ is untouched."
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
        echo "  ├─────────────────────────────────────────────────────┤"
        echo "  │  STABLE  (COPR system install)                      │"
        echo "  │    TTY:          /usr/bin/start-kineticwe           │"
        echo "  │    Login screen: KineticWE                          │"
        echo "  └─────────────────────────────────────────────────────┘"
    else
        echo "  No dev build found at $TEST_PREFIX"
        echo "  (run ./build-rpm-dev.sh --binary first)"
    fi
    echo

    if [[ -f "$SESSION_DIR/$SESSION_DESKTOP" ]]; then
        info "  Login-screen entry: $SESSION_DIR/$SESSION_DESKTOP"
        info "  (log out and pick 'KineticWE-Dev'; the stable 'KineticWE'"
        info "   entry still launches the untouched COPR install)"
    else
        info "  No login-screen entry installed (skipped or sudo declined)."
        info "  Re-run without --no-session to add 'KineticWE-Dev' to the greeter."
    fi
    echo

    if rpm -q "${PACKAGE}" &>/dev/null; then
        local stable_ver
        stable_ver=$(rpm -q "${PACKAGE}" --qf "%{VERSION}-%{RELEASE}" 2>/dev/null || echo "unknown")
        info "  COPR stable version : ${stable_ver}"
    fi

    info "  Dev build release tag : ${DEV_RELEASE}"
    echo

    info "  Since TEST_PREFIX=$TEST_PREFIX is in your PATH, just type:"
    info "    start-kineticwe"
    info "  (from any TTY — no full path needed)"
    echo

    info "Rebuild after making changes:"
    info "  ./build-rpm-dev.sh --binary"
    echo

    info "Full dev build with the Noctalia greeter (installs/activates it if needed):"
    info "  ./build-rpm-dev.sh --full"
    echo

    info "Iterate on a single component (fast, incremental):"
    info "  ./build-rpm-dev.sh --kwin-only    # kwin only"
    info "  ./build-rpm-dev.sh --noct-only    # noctalia shell only"
    echo

    info "Build and auto-install any missing host runtime deps in one step:"
    info "  ./build-rpm-dev.sh --install-host-deps"
    info "  (also installs the default session packages: Breeze icon/cursor themes, color schemes, Qt5/Qt6 tools, Xwayland, portal QML modules, Alacritty)"
    echo

    if find "$RESULTS_DIR" -type f -name "${PACKAGE}*.rpm" ! -name '*.src.rpm' -print0 2>/dev/null | grep -qz .; then
        info "RPM packages:"
        find "$RESULTS_DIR" -type f -name "${PACKAGE}*.rpm" ! -name '*.src.rpm' -exec ls -lh {} \; 2>/dev/null | sed 's/^/  /'
    fi

    info "To remove local dev files and restore pure COPR:"
    info "  ./build-rpm-dev.sh --reset-local"
    echo

    info "RPMs are cached in:"
    info "  $RESULTS_DIR"
    echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local do_install=false
    local do_reset_local=false
    local do_full=false
    local do_binary=false
    local do_kwin_only=false
    local do_noct_only=false
    local do_install_host_deps=false
    local do_session=true

    for arg in "$@"; do
        case "$arg" in
            --install) do_install=true ;;
            --reset-local) do_reset_local=true ;;
            --full)   do_full=true ;;
            --binary) do_binary=true ;;
            --kwin-only) do_kwin_only=true ;;
            --noct-only) do_noct_only=true ;;
            --install-host-deps) do_install_host_deps=true ;;
            --no-session) do_session=false ;;
            --help|-h) echo "Usage: $0 [--install] [--full] [--binary] [--kwin-only] [--noct-only] [--install-host-deps] [--no-session] [--reset-local]"; exit 0 ;;
            *)         warn "Unknown option: $arg";;
        esac
    done

    # --install-host-deps implies the binary build so the dev binaries exist
    # to inspect for missing host libraries (it is a modifier, not a build mode).
    if $do_install_host_deps; then
        do_binary=true
    fi

    if $do_reset_local; then
        echo "=========================================="
        echo "  KineticWE - Reset Local Dev Install"
        echo "=========================================="
        echo
        reset_local
        exit 0
    fi

    if $do_kwin_only; then
        echo "=========================================="
        echo "  KineticWE KWin-Only Dev Build"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo
        check_prereqs
        ensure_distrobox
        kwin_only_build
        exit 0
    fi

    if $do_noct_only; then
        echo "=========================================="
        echo "  KineticWE Noctalia-Only Dev Build"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo
        check_prereqs
        ensure_distrobox
        noctalia_only_build
        exit 0
    fi

    if $do_full || $do_binary; then
        local mode_name
        if $do_full; then
            mode_name="Full Dev Build (binaries + Noctalia greeter)"
        else
            mode_name="Binary Dev Build (no RPM)"
        fi
        echo "=========================================="
        echo "  KineticWE ${mode_name}"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo

        check_prereqs
        setup_distrobox
        binary_build
        if $do_install_host_deps; then
            step "Installing missing host runtime dependencies..."
            TEST_PREFIX="$TEST_PREFIX" "$SCRIPT_DIR/install-runtime-deps.sh"
        fi
        verify_host_deps
        install_startup_script
        if $do_session; then
            install_dev_session_entry
        fi
        if $do_full; then
            # The greeter is a post-build convenience: a failure here must not
            # undo/abort the already-installed dev build, so run it with
            # errexit temporarily off and merely warn on a non-zero result.
            local greeter_rc
            set +e
            setup_noctalia_greeter
            greeter_rc=$?
            set -e
            if [[ $greeter_rc -ne 0 ]]; then
                warn "Noctalia greeter setup did not complete cleanly; the dev build installed."
                warn "Re-run './build-rpm-dev.sh --full' or configure the greeter separately."
            fi
        fi
        print_usage
        exit 0
    fi

    if $do_install; then
        echo "=========================================="
        echo "  KineticWE RPM Dev Install"
        echo "  Version: ${SPEC_VERSION}-${DEV_RELEASE}"
        echo "  Install prefix: ${TEST_PREFIX}"
        echo "=========================================="
        echo

        check_prereqs
        setup_distrobox
        build_rpms
        extract_for_testing
        verify_host_deps
        install_startup_script
        if $do_session; then
            install_dev_session_entry
        fi
        print_usage
        exit 0
    fi

    # Default: build RPMs only, no install
    echo "=========================================="
    echo "  KineticWE RPM Dev Build"
    echo "  Version: ${SPEC_VERSION}-${DEV_RELEASE}"
    echo "  Test prefix: ${TEST_PREFIX}"
    echo "=========================================="
    echo

    check_prereqs
    setup_distrobox
    build_rpms
    extract_for_testing
    verify_host_deps
    install_startup_script
    if $do_session; then
        install_dev_session_entry
    fi
    print_usage
}

main "$@"
