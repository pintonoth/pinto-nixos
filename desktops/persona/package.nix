{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  cavaMonitor =
    inputs.cava-monitor.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        # setBars is invoked by name through Qt's meta-object system upstream.
        patches = (old.patches or [ ]) ++ [ ./cava-monitor.patch ];
      });
  bebasNeue = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/google/fonts/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/bebasneue/BebasNeue-Regular.ttf";
    hash = "sha256-CORiOAUQLYGfWGAeRuNFZIhGB142OyzrIzE8LRyD7HM=";
  };
  fonts = pkgs.runCommand "persona-fonts" { } ''
    mkdir -p $out/share/fonts/truetype
    cp ${bebasNeue} $out/share/fonts/truetype/BebasNeue-Regular.ttf
    cp ${pkgs.montserrat}/share/fonts/ttf/*.ttf $out/share/fonts/truetype/
  '';
  source = pkgs.stdenvNoCC.mkDerivation {
    pname = "persona-quickshell-config";
    version = inputs.persona.shortRev;
    src = inputs.persona;
    nativeBuildInputs = [ pkgs.qt6.qtshadertools ];
    dontWrapQtApps = true;
    patches = [ ./compatibility.patch ];
    postPatch = ''
      # Upstream references these files but does not ship them.
      mkdir -p Assets/fonts
      cp ${fonts}/share/fonts/truetype/{BebasNeue-Regular,Montserrat-Light}.ttf Assets/fonts/
      substituteInPlace Layers/Clock.qml Layers/Calendar.qml \
        --replace-fail 'Microsoft Yahei' 'Noto Sans CJK SC' \
        --replace-fail 'Bahnschrift Condensed' 'Bebas Neue'
      substituteInPlace Layers/Resume.qml \
        --replace-fail 'proggyfonts' 'JetBrainsMono Nerd Font'
    '';
    buildPhase = ''
      runHook preBuild
      # Keep shader bytecode compatible with the Qt used by Quickshell.
      while IFS= read -r -d $'\0' shader; do
        ${lib.getExe' pkgs.qt6.qtshadertools "qsb"} --qt6 -o "$shader.qsb" "$shader"
      done < <(find Assets/shaders -type f \( -name '*.vert' -o -name '*.frag' \) -print0)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r shell.qml Assets Data Layers Widgets $out/
      runHook postInstall
    '';
  };
in
pkgs.runCommand "persona-shell"
  {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    passthru = { inherit source fonts cavaMonitor; };
    meta.mainProgram = "persona-shell";
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${lib.getExe pkgs.quickshell} $out/bin/persona-shell \
      --add-flags '--no-duplicate -p ${source}/shell.qml' \
      --prefix QML_IMPORT_PATH : '${cavaMonitor}/lib/qt6/qml:${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtQmlPrefix}' \
      --prefix QT_PLUGIN_PATH : '${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtPluginPrefix}' \
      --prefix PATH : '${
        lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.gawk
          pkgs.networkmanager
          pkgs.systemd
          pkgs.hyprland
        ]
      }'
  ''
