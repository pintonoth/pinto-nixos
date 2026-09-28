#!/usr/bin/env bash
# kwe-fcitx5-setup — wire fcitx5 into a KineticWE session (new-system setup)
#
# WHY THIS EXISTS (KineticWE-specific; verified against src/ and the live session)
#
#  * KineticWE implements only zwp_input_method_v1 (there is no input-method-v2
#    in the tree) and exposes it — plus zwp_input_panel_v1 — exclusively to the
#    process the compositor spawns itself:
#        InputMethod::startInputMethod()   src/inputmethod.cpp   (private socket)
#        KWinDisplay::allowInterface()     src/wayland_server.cpp:148-156
#    A fcitx5 started from ~/.config/autostart can therefore bind nothing: it
#    gets zero input contexts, never sees keystrokes, and Ctrl+Space has nothing
#    to toggle. That is exactly what fcitx5's own warning describes
#    ("Fcitx should be launched by KWin ... Virtual keyboard -> Fcitx 5").
#
#  * So the COMPOSITOR must own the process, via the same key Plasma's virtual
#    keyboard KCM writes:
#        [Wayland]
#        InputMethod=/usr/share/applications/org.fcitx.Fcitx5.desktop
#    in $KWE_CONFIG_HOME/kineticwe.kwe, read by
#    ApplicationWayland::refreshSettings() -> InputMethod::setInputMethodCommand().
#
#  * The compositor runs with XDG_CONFIG_HOME=$KWE_CONFIG_HOME and
#    XDG_CACHE_HOME=$HOME/.cache/kineticwe (scripts/start-kineticwe.sh:1084-1087).
#    Its child fcitx5 inherits both, so everything fcitx5 spawns (think
#    fcitx5-configtool from its tray menu) resolves its config under
#    ~/.config/kineticwe and misses the user's real ~/.config/qt6ct/qt6ct.conf
#    (Noctalia palette + fonts), ~/.config/qt5ct and ~/.config/fcitx5. The theme
#    symlinks below restore that; the clean fix is a compositor patch handing the
#    input method the real config home (kineticweRealConfigDir()).
#
# WHAT IT CHANGES
#   1. $KWE_CONFIG_HOME/kineticwe.kwe           [Wayland] InputMethod=<desktop file>
#      (in-place patch, every other line untouched; backup written once per run;
#      skip with --no-config when the file is managed declaratively, e.g. by
#      home-manager, where a store symlink must not be replaced)
#   2. $REAL_CONFIG_HOME/autostart/org.fcitx.Fcitx5.desktop
#      standard XDG override with Hidden=true, so the shell's autostart
#      launcher and systemd's xdg-autostart generator both skip it and the
#      compositor's instance is the only one.
#   3. $KWE_CONFIG_HOME/{qt6ct,qt5ct,fcitx5} -> symlinks into the real config
#      home (skip with --no-theme-symlinks).
#   4. $REAL_CONFIG_HOME/environment.d/50-kwe-input-method.conf
#      XMODIFIERS=@im=fcitx for X11/XWayland apps (skip with --no-xmodifiers).
#      NOT QT_IM_MODULE/GTK_IM_MODULE: on a text-input compositor those cause
#      fcitx's blinking candidate window; native Qt/GTK use text-input.
#   5. Stops an already-running fcitx5 that was NOT spawned by the compositor,
#      so the compositor's instance can take the org.fcitx.Fcitx5 D-Bus name.
#
# Idempotent: safe to re-run (after upgrades, or on every fresh install).
# Nothing here restarts your compositor — log out and back in afterwards.
#
# REVERT
#   * delete the [Wayland] InputMethod line from $KWE_CONFIG_HOME/kineticwe.kwe
#   * rm $REAL_CONFIG_HOME/autostart/org.fcitx.Fcitx5.desktop (restore the
#     .bak-fcitx5-setup copy if one was made)
#   * rm $KWE_CONFIG_HOME/{qt6ct,qt5ct,fcitx5}
#   * rm $REAL_CONFIG_HOME/environment.d/50-kwe-input-method.conf
#
# USAGE
#   kwe-fcitx5-setup [--dry-run] [--verify] [--im FILE.desktop]
#                    [--no-theme-symlinks] [--no-xmodifiers] [--no-config]

set -euo pipefail

DRY_RUN=0
VERIFY_ONLY=0
THEME_SYMLINKS=1
XMODIFIERS=1
PATCH_CONFIG=1
IM_DESKTOP=""
DEFAULT_IM_NAME="org.fcitx.Fcitx5.desktop"

say()  { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
run() {
    if ((DRY_RUN)); then
        printf '  [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

usage() {
    sed -n '/^# USAGE/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
    case "$1" in
        -n | --dry-run) DRY_RUN=1 ;;
        --verify) VERIFY_ONLY=1 ;;
        --no-theme-symlinks) THEME_SYMLINKS=0 ;;
        --no-xmodifiers) XMODIFIERS=0 ;;
        --no-config) PATCH_CONFIG=0 ;;
        --im)
            [[ $# -ge 2 ]] || die "--im needs a path to a .desktop file"
            IM_DESKTOP="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "unknown option '$1' (try --help)" ;;
    esac
    shift
done

# --- Paths -------------------------------------------------------------------
# The compositor's private config root (KDirWatch on kineticwe.kwe lives here).
KWE_CONFIG_HOME="${KWE_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/kineticwe}"
# The user's real config home: autostart, environment.d, qt6ct/qt5ct/fcitx5.
REAL_CONFIG_HOME="${KWE_REAL_CONFIG_HOME:-}"
if [[ -z "$REAL_CONFIG_HOME" || "$REAL_CONFIG_HOME" == "$KWE_CONFIG_HOME" ]]; then
    REAL_CONFIG_HOME="$HOME/.config"
fi
KWE_RC="$KWE_CONFIG_HOME/kineticwe.kwe"

# --- Status report (--verify) ------------------------------------------------
report_status() {
    say "KineticWE input-method status"
    say "  compositor config : $KWE_RC"
    if [[ -f "$KWE_RC" ]]; then
        local line
        line="$(grep -m1 '^[[:space:]]*InputMethod[[:space:]]*=' "$KWE_RC" || true)"
        if [[ -n "$line" ]]; then
            say "  InputMethod       : ${line#*=}"
        else
            say "  InputMethod       : (not set)"
        fi
    else
        say "  InputMethod       : (config file does not exist yet)"
    fi

    local pid
    pid="$(pgrep -x fcitx5 | head -1 || true)"
    if [[ -z "$pid" ]]; then
        say "  fcitx5            : not running"
    elif tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -q '^WAYLAND_SOCKET='; then
        say "  fcitx5            : pid $pid — spawned by the compositor (correct)"
    else
        say "  fcitx5            : pid $pid — NOT spawned by the compositor (cannot bind any input method global)"
    fi

    if command -v dbus-send >/dev/null 2>&1; then
        local available
        available="$(dbus-send --session --print-reply --dest=org.kde.KWin /VirtualKeyboard \
            org.freedesktop.DBus.Properties.Get string:org.kde.kwin.VirtualKeyboard string:available 2>/dev/null \
            | tail -1 | grep -o 'true\|false' || true)"
        say "  VirtualKeyboard   : available=${available:-unknown}"
    fi

    local target
    for target in qt6ct qt5ct fcitx5; do
        if [[ -L "$KWE_CONFIG_HOME/$target" ]]; then
            say "  $target symlink     : $(readlink "$KWE_CONFIG_HOME/$target")"
        elif [[ -e "$KWE_CONFIG_HOME/$target" ]]; then
            say "  $target symlink     : MISSING (a real directory sits there instead)"
        else
            say "  $target symlink     : missing"
        fi
    done
}

if ((VERIFY_ONLY)); then
    report_status
    exit 0
fi

# --- Preflight ---------------------------------------------------------------
command -v fcitx5 >/dev/null 2>&1 || die "fcitx5 is not installed (install it first, e.g. 'sudo pacman -S fcitx5 fcitx5-configtool')"
[[ -d "$KWE_CONFIG_HOME" ]] || warn "$KWE_CONFIG_HOME does not exist yet — it is created by the first KineticWE login; writing it now anyway"

# --- 1. Which input method desktop file? -------------------------------------
desktop_exec() {
    awk -F= '
        /^\[/ { in_de = ($0 == "[Desktop Entry]"); next }
        in_de && /^Exec[[:space:]]*=/ { sub(/^Exec[[:space:]]*=[[:space:]]*/, ""); print; exit }
    ' "$1"
}

if [[ -z "$IM_DESKTOP" ]]; then
    IFS=: read -r -a _data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for _dir in "${_data_dirs[@]}"; do
        if [[ -f "$_dir/applications/$DEFAULT_IM_NAME" ]]; then
            IM_DESKTOP="$_dir/applications/$DEFAULT_IM_NAME"
            break
        fi
    done
fi
[[ -n "$IM_DESKTOP" ]] || die "could not find $DEFAULT_IM_NAME in \$XDG_DATA_DIRS/applications — pass --im <file.desktop>"

if [[ ! -f "$IM_DESKTOP" ]]; then
    warn "$IM_DESKTOP does not exist"
fi
IM_EXEC="$(desktop_exec "$IM_DESKTOP" || true)"
[[ -n "$IM_EXEC" ]] || die "$IM_DESKTOP has no Exec= line"
IM_PROGRAM="${IM_EXEC%% *}"
[[ -x "$IM_PROGRAM" ]] || warn "Exec points at '$IM_PROGRAM', which is not executable"
if ! grep -q '^X-KDE-Wayland-VirtualKeyboard=true' "$IM_DESKTOP" 2>/dev/null; then
    warn "$IM_DESKTOP lacks X-KDE-Wayland-VirtualKeyboard=true (not a compositor-launchable input method)"
fi

say "input method      : $IM_DESKTOP (Exec=$IM_EXEC)"

# --- 2. Patch the compositor config ------------------------------------------
patch_config() {
    python3 - "$KWE_RC" "$IM_DESKTOP" <<'PY'
import os
import re
import sys

path, value = sys.argv[1], sys.argv[2]
header = re.compile(r"^\s*\[([^\]]*)\]\s*$")
entry = "InputMethod=%s" % value

lines = []
if os.path.exists(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        lines = fh.read().splitlines(keepends=True)

idx = None
for i, line in enumerate(lines):
    m = header.match(line)
    if m and m.group(1) == "Wayland":
        idx = i
        break

changed = False
if idx is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append("\n[Wayland]\n")
    lines.append(entry + "\n")
    changed = True
else:
    end = len(lines)
    for j in range(idx + 1, len(lines)):
        if header.match(lines[j]):
            end = j
            break
    for j in range(idx + 1, end):
        if re.match(r"^\s*InputMethod\s*=", lines[j]):
            if lines[j].rstrip("\n") != entry:
                lines[j] = entry + "\n"
                changed = True
            break
    else:
        lines.insert(idx + 1, entry + "\n")
        changed = True

if changed:
    tmp = path + ".tmp-kwe-fcitx5-setup"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.writelines(lines)
    os.replace(tmp, path)

print("changed" if changed else "unchanged")
PY
}

if ((PATCH_CONFIG == 0)); then
    say "compositor config : skipped (--no-config); keep [Wayland] InputMethod=$IM_DESKTOP in the managed file"
elif ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is missing — cannot patch $KWE_RC automatically; add this by hand:"
    warn "    [Wayland]"
    warn "    InputMethod=$IM_DESKTOP"
elif ((DRY_RUN)); then
    say "compositor config : would set [Wayland] InputMethod=$IM_DESKTOP in $KWE_RC"
else
    _bak="$KWE_RC.bak-fcitx5-setup"
    if [[ -f "$KWE_RC" && ! -e "$_bak" ]]; then
        cp -p "$KWE_RC" "$_bak"
        note "backup: $_bak"
    fi
    _result="$(patch_config)"
    if [[ "$_result" == changed ]]; then
        say "compositor config : [Wayland] InputMethod set in $KWE_RC"
    else
        say "compositor config : already correct in $KWE_RC"
    fi
fi

# --- 3. One launcher only: hide the XDG autostart entry ----------------------
AUTOSTART_DIR="$REAL_CONFIG_HOME/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/$DEFAULT_IM_NAME"

# Writes the XDG override; returns 0 when it changed the file, 1 when it was
# already identical (so re-runs report honestly).
write_autostart_override() {
    mkdir -p "$AUTOSTART_DIR"
    local content
    content="$(cat <<EOF
[Desktop Entry]
Type=Application
Name=Fcitx 5
GenericName=Input Method
Comment=Start Input Method
Exec=$IM_EXEC
Terminal=false
NoDisplay=true
# Hidden on purpose: the KineticWE compositor owns the fcitx5 process (it must:
# only a compositor-spawned client gets zwp_input_method_v1 / zwp_input_panel_v1).
# A second, autostarted instance would be inert and race for org.fcitx.Fcitx5.
# Managed by kwe-fcitx5-setup; remove this file to let autostart launch fcitx5.
Hidden=true
X-GNOME-Autostart-enabled=false
X-KineticWE-InputMethod=compositor-managed
EOF
)"
    if [[ -f "$AUTOSTART_FILE" && "$(cat "$AUTOSTART_FILE")" == "$content" ]]; then
        return 1
    fi
    if [[ -f "$AUTOSTART_FILE" ]] && ! grep -q '^Hidden=true' "$AUTOSTART_FILE"; then
        cp -p "$AUTOSTART_FILE" "$AUTOSTART_FILE.bak-fcitx5-setup"
        note "backup: $AUTOSTART_FILE.bak-fcitx5-setup"
    fi
    printf '%s\n' "$content" >"$AUTOSTART_FILE"
    return 0
}

if ((DRY_RUN)); then
    say "autostart         : would write Hidden=true override at $AUTOSTART_FILE"
else
    if write_autostart_override; then
        say "autostart         : Hidden=true override written at $AUTOSTART_FILE"
    else
        say "autostart         : Hidden=true override already present at $AUTOSTART_FILE"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
fi

# --- 4. Theme symlinks into the real config home -----------------------------
symlink_into_real_home() {
    local name="$1" target="$REAL_CONFIG_HOME/$1" link="$KWE_CONFIG_HOME/$1"
    mkdir -p "$target"
    if [[ -L "$link" ]]; then
        if [[ "$(readlink "$link")" == "$target" ]]; then
            note "$name: already linked"
            return 0
        fi
        warn "$name: $link points elsewhere ($(readlink "$link")) — leaving it alone"
        return 0
    fi
    if [[ -e "$link" ]]; then
        if [[ -z "$(find "$link" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            rmdir "$link"
        else
            mv "$link" "$link.leaked-env-bak"
            note "$name: moved the compositor-env copy to $link.leaked-env-bak"
        fi
    fi
    ln -s "$target" "$link"
    note "$name: $link -> $target"
}

if ((THEME_SYMLINKS)); then
    if ((DRY_RUN)); then
        say "theme symlinks    : would link qt6ct, qt5ct, fcitx5 under $KWE_CONFIG_HOME"
    else
        say "theme symlinks    : fcitx5's children (e.g. fcitx5-configtool) read these"
        symlink_into_real_home qt6ct
        symlink_into_real_home qt5ct
        symlink_into_real_home fcitx5
    fi
fi

# --- 5. XMODIFIERS for X11 / XWayland apps -----------------------------------
ENV_D_DIR="$REAL_CONFIG_HOME/environment.d"
ENV_D_FILE="$ENV_D_DIR/50-kwe-input-method.conf"
if ((XMODIFIERS)); then
    if ((DRY_RUN)); then
        say "XMODIFIERS        : would write XMODIFIERS=@im=fcitx to $ENV_D_FILE"
    else
        mkdir -p "$ENV_D_DIR"
        if [[ -f "$ENV_D_FILE" ]] && grep -q '^XMODIFIERS=@im=fcitx' "$ENV_D_FILE"; then
            say "XMODIFIERS        : already set in $ENV_D_FILE"
        else
            cat >"$ENV_D_FILE" <<'EOF'
# X11 / XWayland apps find fcitx5 through XIM. Native Qt/GTK apps do NOT need
# QT_IM_MODULE/GTK_IM_MODULE on KineticWE: they use text-input, which the
# compositor routes to the fcitx5 process it spawns (see kwe-fcitx5-setup).
XMODIFIERS=@im=fcitx
EOF
            say "XMODIFIERS        : written to $ENV_D_FILE"
        fi
        # Note: only reaches processes started through the systemd user manager
        # (D-Bus activation, user units). Apps launched by the shell inherit the
        # session script's environment instead.
        note "note: this reaches systemd/D-Bus-started apps; apps launched by the shell inherit the"
        note "      session script's environment — export XMODIFIERS=@im=fcitx there for those."
    fi
fi

# --- 6. Let the compositor own the running instance --------------------------
IM_PID="$(pgrep -x fcitx5 | head -1 || true)"
if [[ -n "$IM_PID" ]]; then
    if tr '\0' '\n' <"/proc/$IM_PID/environ" 2>/dev/null | grep -q '^WAYLAND_SOCKET='; then
        say "running fcitx5    : pid $IM_PID is already compositor-managed — leaving it"
    elif command -v fcitx5-remote >/dev/null 2>&1 && fcitx5-remote --check >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            say "running fcitx5    : would quit pid $IM_PID (fcitx5-remote -e)"
        else
            fcitx5-remote -e || true
            for _ in $(seq 1 10); do
                pgrep -x fcitx5 >/dev/null || break
                sleep 0.5
            done
            if pgrep -x fcitx5 >/dev/null; then
                warn "fcitx5 is still running — quit it manually so the compositor's instance can take over"
            else
                say "running fcitx5    : quit the non-compositor instance"
            fi
        fi
    else
        warn "a fcitx5 (pid $IM_PID) started outside the compositor is running; run 'fcitx5-remote -e' before logging out so the compositor's instance can take the D-Bus name"
    fi
fi

# --- Summary -----------------------------------------------------------------
say ""
say "done. next steps:"
say "  1. log out of KineticWE and back in (the compositor reads [Wayland] InputMethod at startup;"
say "     it does not re-read it live on every build)."
say "  2. verify:  $0 --verify"
say "  3. then focus a text field and press Ctrl+Space (fcitx5 default trigger key)."
say "     X11 apps additionally need a re-login for XMODIFIERS to be exported."
