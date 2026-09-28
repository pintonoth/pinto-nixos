#!/usr/bin/env bash
# kwe-fcitx5-setup — wire fcitx5 into a KineticWE session (new-system setup)
#
# WHY THIS EXISTS (KineticWE-specific; verified against src/ and the live session)
#
#  * KineticWE implements only zwp_input_method_v1 (there is no input-method-v2
#    anywhere in the tree) and exposes it — plus zwp_input_panel_v1 — only to the
#    process the compositor spawns itself:
#        InputMethod::startInputMethod()   src/inputmethod.cpp        (private socket)
#        KWinDisplay::allowInterface()     src/wayland_server.cpp:148-156
#    A fcitx5 started from ~/.config/autostart can therefore bind nothing: zero
#    input contexts, no keystrokes, nothing for Ctrl+Space to toggle — exactly
#    what fcitx5's own warning describes ("Fcitx should be launched by KWin ...
#    Virtual keyboard -> Fcitx 5").
#
#  * So the COMPOSITOR must own the process, via the key Plasma's virtual-keyboard
#    KCM writes:
#        [Wayland]
#        InputMethod=<absolute path to a .desktop file>
#    in $KWE_CONFIG_HOME/kineticwe.kwe, read by ApplicationWayland::refreshSettings()
#    -> InputMethod::setInputMethodCommand(); the compositor runs that entry's Exec.
#
#  * The compositor runs with XDG_CONFIG_HOME=$KWE_CONFIG_HOME and
#    XDG_CACHE_HOME=$HOME/.cache/kineticwe (scripts/start-kineticwe.sh:1084-1087).
#    Its child fcitx5 — and everything fcitx5 spawns, e.g. fcitx5-configtool from
#    its tray menu — inherits that, so qt6ct looks for its config in
#    ~/.config/kineticwe/qt6ct/ (absent -> default light palette, the "white
#    theme"), and fcitx5 writes its own config into ~/.config/kineticwe/fcitx5/,
#    which the session script's step 4d prune (scripts/start-kineticwe.sh:259-286)
#    deletes on every login — silently resetting the user's fcitx5 settings.
#
#  * Fix, without touching the compositor or the session script: point InputMethod
#    at a small user-level desktop entry whose Exec hands fcitx5 the user's real
#    config/cache homes explicitly, before starting it:
#        Exec=/usr/bin/env XDG_CONFIG_HOME=/home/USER/.config \
#             XDG_CACHE_HOME=/home/USER/.cache /usr/bin/fcitx5
#    The paths are baked in by this script for the machine it runs on
#    ($REAL_CONFIG_HOME / $REAL_CACHE_HOME below), so nothing is hardcoded to one
#    user and re-running the script refreshes them elsewhere.
#
#    Why explicit values rather than `env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME`:
#    unsetting only works where every consumer implements the XDG fallback to
#    $HOME/.config / $HOME/.cache, and fcitx5 resolves its own directory by reading
#    that variable itself (the literal "XDG_CONFIG_HOME" is in libFcitx5Utils.so),
#    not through Qt's QStandardPaths. The explicit form is the one verified end to
#    end; --unset-form emits the unset variant instead (needs a fresh login to take
#    effect, and is only worth it if you want to test that path).
#
#    Either way /usr/bin/env uses execvp — it does not fork — so the compositor's
#    process tracking, its crash-restart bookkeeping and the inherited
#    WAYLAND_SOCKET fd keep working on fcitx5 itself. And do NOT instead symlink
#    ~/.config/qt6ct (or qt5ct, fcitx5) into $KWE_CONFIG_HOME: step 4d prunes
#    everything there that is not compositor-owned, so such links die at login.
#
# WHAT IT CHANGES
#   1. $XDG_DATA_HOME/applications/kwe-fcitx5.desktop
#      the wrapper entry above, with X-KDE-Wayland-VirtualKeyboard=true so Kinetic
#      Settings' Virtual Keyboard page lists it. Its Exec is derived from the stock
#      fcitx5 entry (see --im). Skip the wrapper with --no-wrapper: InputMethod then
#      points straight at the stock entry (debugging / upstream parity).
#   2. $KWE_CONFIG_HOME/kineticwe.kwe     [Wayland] InputMethod=<wrapper entry>
#      (in-place patch, every other line untouched; one backup per run; skip with
#      --no-config when that file is managed declaratively, e.g. by home-manager,
#      where a store symlink must not be replaced)
#   3. $REAL_CONFIG_HOME/autostart/org.fcitx.Fcitx5.desktop
#      standard XDG override with Hidden=true, so the shell's autostart launcher
#      and systemd's xdg-autostart generator both skip it and the compositor's
#      instance is the only one.
#   4. $REAL_CONFIG_HOME/environment.d/50-kwe-input-method.conf
#      XMODIFIERS=@im=fcitx for X11/XWayland apps (skip with --no-xmodifiers).
#      NOT QT_IM_MODULE/GTK_IM_MODULE: on a text-input compositor those cause
#      fcitx's blinking candidate window; native Qt/GTK apps use text-input.
#   5. Stops a running fcitx5 that was NOT spawned by the compositor, so the
#      compositor's instance can take the org.fcitx.Fcitx5 D-Bus name.
#
# The compositor reads the entry's Exec at startup, or when kineticwe.kwe changes —
# editing the entry alone is not a live reload. Log out and back in afterwards
# (--verify prints fcitx5's live XDG_CONFIG_HOME so you can confirm it took).
#
# REVERT
#   * rm $XDG_DATA_HOME/applications/kwe-fcitx5.desktop  (or re-run with --no-wrapper)
#   * restore [Wayland] InputMethod in $KWE_CONFIG_HOME/kineticwe.kwe (see the
#     .bak-fcitx5-setup copy written by the first run)
#   * rm $REAL_CONFIG_HOME/autostart/org.fcitx.Fcitx5.desktop (restore its
#     .bak-fcitx5-setup copy if one was made)
#   * rm $REAL_CONFIG_HOME/environment.d/50-kwe-input-method.conf
#
# USAGE
#   kwe-fcitx5-setup [--dry-run] [--verify] [--im FILE.desktop]
#                    [--no-wrapper] [--unset-form] [--no-config] [--no-xmodifiers]

set -euo pipefail

DRY_RUN=0
VERIFY_ONLY=0
WRAPPER=1
UNSET_FORM=0
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
        --no-wrapper) WRAPPER=0 ;;
        --unset-form) UNSET_FORM=1 ;;
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
# The real config/cache homes are baked into the wrapper entry's Exec, so they must
# be the real ones even when this script runs from a compositor-influenced shell.
REAL_CONFIG_HOME="${KWE_REAL_CONFIG_HOME:-}"
if [[ -z "$REAL_CONFIG_HOME" || "$REAL_CONFIG_HOME" == "$KWE_CONFIG_HOME" ]]; then
    REAL_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    [[ "$REAL_CONFIG_HOME" == "$KWE_CONFIG_HOME" ]] && REAL_CONFIG_HOME="$HOME/.config"
fi
REAL_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ "$REAL_CACHE_HOME" == "$HOME/.cache/kineticwe" || "$REAL_CACHE_HOME" == "$KWE_CONFIG_HOME"* ]]; then
    REAL_CACHE_HOME="$HOME/.cache"
fi
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
KWE_RC="$KWE_CONFIG_HOME/kineticwe.kwe"
ENTRY_FILE="$DATA_HOME/applications/kwe-fcitx5.desktop"

# Reads a key from the [Desktop Entry] group.
desktop_value() { # file key
    awk -F= -v want="$2" '
        /^\[/ { in_de = ($0 == "[Desktop Entry]"); next }
        in_de && $1 == want { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
    ' "$1"
}

env_of_pid() { # pid varname
    tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p"
}

# --- Status report (--verify) ------------------------------------------------
report_status() {
    local cfg_input="" pid env_config env_cache entry_exec baked
    say "KineticWE input-method status"
    say "  compositor config : $KWE_RC"
    if [[ -f "$KWE_RC" ]]; then
        cfg_input="$(awk -F= '/^\[Wayland\]/{f=1;next} /^\[/{f=0} f && $1=="InputMethod"{sub(/^[^=]*=/,"");print;exit}' "$KWE_RC")"
    fi
    say "  InputMethod       : ${cfg_input:-(not set)}"
    if [[ -n "$cfg_input" ]]; then
        if [[ "$cfg_input" == "$ENTRY_FILE" ]]; then
            say "  wrapper entry     : in use"
        else
            say "  wrapper entry     : NOT in use (InputMethod points at $cfg_input)"
        fi
    fi
    if [[ -f "$ENTRY_FILE" ]]; then
        entry_exec="$(desktop_value "$ENTRY_FILE" Exec)"
        say "  entry Exec        : $entry_exec"
        baked="$(printf '%s' "$entry_exec" | grep -o 'XDG_CONFIG_HOME=[^ ]*' | head -1 | cut -d= -f2 | tr -d '"')"
        if [[ -n "$baked" && "$baked" != "$REAL_CONFIG_HOME" ]]; then
            say "                      ^ baked for '$baked', this machine's config home is"
            say "                        '$REAL_CONFIG_HOME' — re-run to refresh the entry"
        fi
        if [[ -z "$baked" ]] && ! printf '%s' "$entry_exec" | grep -q -- '-u XDG_CONFIG_HOME'; then
            say "                      ^ fcitx5 gets no XDG_CONFIG_HOME: it inherits the kineticwe root"
        fi
    else
        say "  entry Exec        : (missing: $ENTRY_FILE)"
    fi

    pid="$(pgrep -x fcitx5 | head -1 || true)"
    if [[ -z "$pid" ]]; then
        say "  fcitx5            : not running"
    else
        if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -q '^WAYLAND_SOCKET='; then
            say "  fcitx5            : pid $pid — spawned by the compositor (correct)"
        else
            say "  fcitx5            : pid $pid — NOT spawned by the compositor (cannot bind any input method global)"
        fi
        env_config="$(env_of_pid "$pid" XDG_CONFIG_HOME)"
        env_cache="$(env_of_pid "$pid" XDG_CACHE_HOME)"
        say "  fcitx5 XDG_CONFIG : ${env_config:-(unset -> \$HOME/.config)}"
        say "  fcitx5 XDG_CACHE  : ${env_cache:-(unset -> \$HOME/.cache)}"
        if [[ "$env_config" == "$KWE_CONFIG_HOME" ]]; then
            say "                      ^ still redirected: the wrapper is not active yet (log out/in)"
        fi
    fi

    if command -v dbus-send >/dev/null 2>&1; then
        say "  VirtualKeyboard   : available=$(dbus-send --session --print-reply --dest=org.kde.KWin /VirtualKeyboard \
            org.freedesktop.DBus.Properties.Get string:org.kde.kwin.VirtualKeyboard string:available 2>/dev/null \
            | tail -1 | grep -o 'true\|false' || echo unknown)"
    fi
}

if ((VERIFY_ONLY)); then
    report_status
    exit 0
fi

# --- Preflight ---------------------------------------------------------------
command -v fcitx5 >/dev/null 2>&1 || die "fcitx5 is not installed (install it first, e.g. 'sudo pacman -S fcitx5 fcitx5-configtool')"
[[ -d "$KWE_CONFIG_HOME" ]] || warn "$KWE_CONFIG_HOME does not exist yet — it is created by the first KineticWE login; writing it now anyway"

# --- 1. Stock entry: which binary should the wrapper start? ------------------
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
[[ -f "$IM_DESKTOP" ]] || warn "$IM_DESKTOP does not exist"

IM_EXEC="$(desktop_value "$IM_DESKTOP" Exec)"
[[ -n "$IM_EXEC" ]] || die "$IM_DESKTOP has no Exec= line"
IM_PROGRAM="${IM_EXEC%% *}"
IM_ICON="$(desktop_value "$IM_DESKTOP" Icon)"
[[ -x "$IM_PROGRAM" ]] || warn "Exec points at '$IM_PROGRAM', which is not executable"
ENV_BIN="$(command -v env || true)"
[[ -n "$ENV_BIN" ]] || die "the 'env' utility is required for the wrapper entry"
if ! grep -q '^X-KDE-Wayland-VirtualKeyboard=true' "$IM_DESKTOP" 2>/dev/null; then
    warn "$IM_DESKTOP lacks X-KDE-Wayland-VirtualKeyboard=true (not a compositor-launchable input method)"
fi
say "stock entry       : $IM_DESKTOP (Exec=$IM_EXEC)"

IM_TARGET="$IM_DESKTOP"
((WRAPPER)) && IM_TARGET="$ENTRY_FILE"

# The command line the compositor will run, i.e. the wrapper entry's Exec line.
if ((UNSET_FORM)); then
    IM_EXEC_LINE="$ENV_BIN -u XDG_CONFIG_HOME -u XDG_CACHE_HOME $IM_PROGRAM"
else
    IM_EXEC_LINE="$ENV_BIN XDG_CONFIG_HOME=$REAL_CONFIG_HOME XDG_CACHE_HOME=$REAL_CACHE_HOME $IM_PROGRAM"
fi

# --- 2. The wrapper entry ----------------------------------------------------
# Returns 0 when the file changed, 1 when it was already identical.
write_wrapper_entry() {
    mkdir -p "$DATA_HOME/applications"
    local content
    content="$(cat <<EOF
[Desktop Entry]
Type=Application
Name=Fcitx 5 (KineticWE)
GenericName=Input Method
Comment=Compositor-managed fcitx5 with the user's real XDG config/cache home
Exec=$IM_EXEC_LINE
Icon=${IM_ICON:-fcitx}
Terminal=false
NoDisplay=true
StartupNotify=false
# The KineticWE compositor owns the fcitx5 process: only a compositor-spawned
# client receives zwp_input_method_v1 / zwp_input_panel_v1 (no input-method-v2 in
# the tree), so an autostarted fcitx5 can never work (see kwe-fcitx5-setup).
X-KDE-Wayland-VirtualKeyboard=true
X-KDE-Wayland-Interfaces=org_kde_plasma_window_management
# XDG_CONFIG_HOME / XDG_CACHE_HOME are set to the user's real homes on purpose: the
# compositor runs with them redirected to the kineticwe root
# (scripts/start-kineticwe.sh), which hides ~/.config/qt6ct (Noctalia palette and
# fonts) from fcitx5's tools and makes fcitx5 write its config into a root that the
# session script prunes on every login. Generated by kwe-fcitx5-setup.
X-KineticWE-InputMethod=config-home-wrapper
EOF
)"
    if [[ -f "$ENTRY_FILE" && "$(cat "$ENTRY_FILE")" == "$content" ]]; then
        return 1
    fi
    printf '%s\n' "$content" >"$ENTRY_FILE"
    return 0
}

if ((WRAPPER)); then
    if ((DRY_RUN)); then
        say "wrapper entry     : would write $ENTRY_FILE"
        say "                    Exec=$IM_EXEC_LINE"
    elif write_wrapper_entry; then
        say "wrapper entry     : written to $ENTRY_FILE"
        say "                    Exec=$IM_EXEC_LINE"
        if command -v kbuildsycoca6 >/dev/null 2>&1; then
            kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
        fi
    else
        say "wrapper entry     : already up to date at $ENTRY_FILE"
    fi
else
    say "wrapper entry     : skipped (--no-wrapper)"
fi

# --- 3. Point the compositor at the entry ------------------------------------
patch_config() {
    python3 - "$KWE_RC" "$1" <<'PY'
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
    say "compositor config : skipped (--no-config); keep [Wayland] InputMethod=$IM_TARGET in the managed file"
elif ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is missing — cannot patch $KWE_RC automatically; add this by hand:"
    warn "    [Wayland]"
    warn "    InputMethod=$IM_TARGET"
elif ((DRY_RUN)); then
    say "compositor config : would set [Wayland] InputMethod=$IM_TARGET in $KWE_RC"
else
    _bak="$KWE_RC.bak-fcitx5-setup"
    if [[ -f "$KWE_RC" && ! -e "$_bak" ]]; then
        cp -p "$KWE_RC" "$_bak"
        note "backup: $_bak"
    fi
    if [[ "$(patch_config "$IM_TARGET")" == changed ]]; then
        say "compositor config : [Wayland] InputMethod=$IM_TARGET in $KWE_RC"
    else
        say "compositor config : already correct in $KWE_RC"
    fi
fi

# --- 4. One launcher only: hide the XDG autostart entry ----------------------
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
        if [[ "$(env_of_pid "$IM_PID" XDG_CONFIG_HOME)" == "$KWE_CONFIG_HOME" ]]; then
            note "it still uses the redirected config home; the wrapper takes effect on the next login"
        fi
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
say "  1. log out of KineticWE and back in — the compositor reads [Wayland] InputMethod and"
say "     the entry's Exec at startup (editing the entry alone is not a live reload)."
say "  2. verify:  $0 --verify   (fcitx5 XDG_CONFIG should be $REAL_CONFIG_HOME, not the ke root)"
say "  3. focus a text field and press Ctrl+Space (fcitx5 default trigger key)."
say "     X11 apps additionally need a re-login for XMODIFIERS to be exported."
if ((WRAPPER)); then
    say "  4. note: selecting an entry in Kinetic Settings -> Virtual Keyboard rewrites"
    say "     [Wayland] InputMethod back to the stock desktop file and drops the wrapper;"
    say "     re-run this script if that happens."
    say "  5. deploying this dotfiles tree to another machine or user? re-run the script"
    say "     there: the entry's Exec bakes that machine's real config/cache paths."
fi
