{
  pkgs,
  persona,
  hyprlandConfig,
}:
let
  testConfig = pkgs.writeText "persona-test.json" (
    builtins.toJSON {
      shell = "${persona}/bin/persona-shell";
      source = persona.source;
      sway = "${pkgs.sway}/bin/sway";
      wtype = "${pkgs.wtype}/bin/wtype";
      grim = "${pkgs.grim}/bin/grim";
      touch = "${pkgs.coreutils}/bin/touch";
    }
  );
in
pkgs.runCommand "persona-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.dbus
    ];
    FONTCONFIG_FILE = pkgs.makeFontsConf {
      fontDirectories = [
        persona.fonts
        pkgs.libertine
        pkgs.material-symbols
        pkgs.noto-fonts-cjk-sans
        pkgs.nerd-fonts.jetbrains-mono
      ];
    };
    LIBGL_ALWAYS_SOFTWARE = "1";
    LIBGL_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";
    __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
  }
  ''
    mkdir -p $out "$TMPDIR/runtime"
    chmod 700 "$TMPDIR/runtime"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    ${pkgs.hyprland}/bin/Hyprland --verify-config -c ${hyprlandConfig} > $out/hyprland.log 2>&1
    grep -q 'config ok' $out/hyprland.log
    dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- python ${./smoke-test.py} ${testConfig} "$out"
  ''
