{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  qt6,
  glm,
  immer,
  openssl,
  zlib,
}:

stdenv.mkDerivation {
  pname = "mmapper";
  version = "26.06.0";

  src = fetchFromGitHub {
    owner = "MUME";
    repo = "MMapper";
    rev = "5773a7eac22f23ca71a28b9702ce5e6efa7a3831"; # v26.06.0
    hash = "sha256-ENYzphqBSHkUBSAO6fFdJGMzNYoO5whq4mGEr6QgpCw=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtsvg
    glm
    immer
    openssl
    zlib
  ];

  cmakeFlags = [
    # Every option that downloads data or talks to update services is off,
    # so the build stays offline and the client starts with an empty map.
    "-DWITH_AUDIO=OFF"
    "-DWITH_IMAGES=OFF"
    "-DWITH_MAP=OFF"
    "-DWITH_QTKEYCHAIN=OFF"
    "-DWITH_UPDATER=OFF"
    "-DWITH_WEBSOCKET=OFF"
    # Use the system headers instead of upstream's download fallback.
    "-DGLM_INCLUDE_DIR=${glm}/include"
    "-DIMMER_INCLUDE_DIR=${immer}/include"
    # The source has no .git; fix the otherwise current build date to the
    # release commit date.
    "-DMMAPPER_BUILD_DATE=2026-06-05"
  ];

  # GLM 1.x requires an explicit opt-in for the gtx headers MMapper uses.
  env.NIX_CFLAGS_COMPILE = "-DGLM_ENABLE_EXPERIMENTAL";

  # Upstream QtTest programs create widgets; run them headless, once each.
  doCheck = true;
  enableParallelChecking = false;
  preCheck = ''
    export QT_QPA_PLATFORM=offscreen
    export HOME=$TMPDIR
  '';

  # The Linux install rule always installs the asset directory, even with
  # every downloaded asset disabled.
  preInstall = ''
    mkdir -p assets
  '';

  postInstall = ''
    doc=$out/share/doc/mmapper
    install -Dm644 -t $doc \
      ../COPYING.txt ../AUTHORS.txt ../README.md ../NEWS.md \
      ../src/resources/LICENSE.{BOOST,GLM,LGPL,OPENSSL,QTKEYCHAIN}
    install -Dm644 ../src/resources/fonts/LICENSE $doc/LICENSE.FONTS
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/mmapper
    test -f $out/share/applications/org.mume.MMapper.desktop
    test -f $out/share/doc/mmapper/COPYING.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical client and mapper for the MUME multi-user dungeon";
    longDescription = ''
      MMapper is a graphical client and mapper for MUME.  It provides a
      local Telnet proxy, map editing and rendering, pathfinding and logs.
      This build disables the update checker, downloaded default map, image
      and audio assets, QtKeychain credential storage and WebSocket support,
      so it starts with an empty map.
    '';
    homepage = "https://github.com/MUME/MMapper";
    license = [
      lib.licenses.gpl2Plus
      lib.licenses.ofl
      lib.licenses.bitstreamVera
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "mmapper";
  };
}
