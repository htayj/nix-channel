{ lib
, stdenvNoCC
, fetchFromGitHub
, python3
, xkbcomp
, coreutils
, gawk
, runtimeShell
}:

let
  pythonEnv = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenvNoCC.mkDerivation {
  pname = "manna-cadet";
  # Upstream publishes no releases; Guix packages this commit as
  # 20260809-1.e5f7e81.
  version = "0-unstable-e5f7e81";

  src = fetchFromGitHub {
    owner = "htayj";
    repo = "manna-cadet";
    rev = "e5f7e81cdb6e30a7735cdcab622ede29007e379b";
    hash = "sha256-dQwp4GhrOz9hhD1VagK6RFzlMb0kRufj+LBegiT8OgY=";
  };

  nativeBuildInputs = [ pythonEnv ];

  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    patchShebangs draw-kanata-keymap.py reload-spacecadet-xkb.sh
  '';

  # Exercise the converter against the primary layered layout.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 draw-kanata-keymap.py \
      --kanata kanata/kinesis.advantage2.layered.kanata.kbd \
      --xkb xkb/symbols/spacecadet \
      --qmk-info-json kinesis.qmk.json \
      --output-yaml manna-cadet-check.yaml
    test -s manna-cadet-check.yaml
    rm manna-cadet-check.yaml
    runHook postCheck
  '';

  # The reload helper calls xkbcomp, tr, id and awk; the wrapper provides them
  # and defaults to the bundled keymap instead of a copy under $HOME.  SVG
  # rendering needs a user-supplied keymap-drawer and is optional.
  installPhase = ''
    runHook preInstall

    install -Dm555 -t $out/libexec/manna-cadet \
      draw-kanata-keymap.py reload-spacecadet-xkb.sh
    mkdir -p $out/share/manna-cadet
    cp -r kanata xkb drawings $out/share/manna-cadet/
    install -Dm444 -t $out/share/manna-cadet kinesis.qmk.json
    install -Dm444 -t $out/share/doc/manna-cadet \
      LICENSE README.md space-cadet-layered-mnemonics.md

    mkdir -p $out/bin
    cat > $out/bin/manna-cadet-draw-keymap <<'EOF'
    #!${runtimeShell}
    exec ${pythonEnv}/bin/python3 ${placeholder "out"}/libexec/manna-cadet/draw-kanata-keymap.py "$@"
    EOF
    cat > $out/bin/manna-cadet-reload-spacecadet-xkb <<'EOF'
    #!${runtimeShell}
    export PATH="${lib.makeBinPath [ xkbcomp coreutils gawk ]}''${PATH:+:$PATH}"
    exec ${placeholder "out"}/libexec/manna-cadet/reload-spacecadet-xkb.sh \
      "''${1:-${placeholder "out"}/share/manna-cadet/xkb/keymap/spacecadet.xkb}" \
      "''${2:-${placeholder "out"}/share/manna-cadet/xkb}"
    EOF
    chmod 555 $out/bin/manna-cadet-draw-keymap \
      $out/bin/manna-cadet-reload-spacecadet-xkb

    runHook postInstall
  '';

  meta = {
    description = "Space Cadet keyboard layouts and tools for Kinesis keyboards";
    longDescription = ''
      Manna Cadet provides Space Cadet-inspired Kanata layouts and XKB files
      for Kinesis Advantage 2 and Advantage 360 keyboards.  It includes the
      manna-cadet-draw-keymap converter for generating keymap-drawer YAML,
      the manna-cadet-reload-spacecadet-xkb helper for applying the bundled
      XKB keymap, layered-layout mnemonic notes, and generated reference
      drawings.
    '';
    homepage = "https://github.com/htayj/manna-cadet";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "manna-cadet-draw-keymap";
  };
}
