{
  lib,
  llvmPackages_21,
  fetchFromGitHub,
  cmake,
  pkg-config,
  makeShellWrapper,
  copyDesktopItems,
  makeDesktopItem,
  qt6,
  gtest,
  libssh,
  luajit,
  openssl,
  pcre,
  sqlite,
  zlib,
}:

# Upstream writes C++26 and builds it with Clang in its own CI.
llvmPackages_21.stdenv.mkDerivation {
  pname = "mushkin";
  version = "0.5.1";

  src = fetchFromGitHub {
    owner = "justinpopa";
    repo = "mushkin";
    rev = "1199f8e68167eee07123f08983fdf5f775b7c5bd"; # v0.5.1
    # external/yuescript is a submodule.
    fetchSubmodules = true;
    hash = "sha256-+vTqaiaPcjqDflf12glw1Ju7jxBlO1oExVoWCkBB0EQ=";
  };

  # The release commits these files with CRLF line endings; the patch is
  # written against their LF form.
  prePatch = ''
    sed -i 's/\r$//' \
      CMakeLists.txt \
      src/main.cpp \
      src/utils/app_paths.cpp \
      src/utils/app_paths.h \
      src/world/script_engine.cpp \
      src/world/sound_manager.cpp \
      src/world/lua_api/world_info.cpp \
      tests/CMakeLists.txt \
      tests/test_lua_api_gtest.cpp \
      tests/test_telnet_parser_gtest.cpp
  '';

  patches = [
    # Report the released version, use the packaged GoogleTest instead of
    # downloading one, load the bundled Lua runtime from beside the
    # executable, keep mutable state in MUSHKIN_HOME or the XDG data
    # directory, and refuse MSP sound filenames that carry a path.
    ./runtime-security.patch
  ];

  # These files use QElapsedTimer without including it; Qt 6.12 no longer
  # pulls the header in through the others.
  postPatch = ''
    sed -i '1i #include <QElapsedTimer>' \
      src/world/lua_api/world_plugins.cpp \
      src/world/lua_api/world_settings.cpp \
      src/ui/views/output_view.cpp
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
    makeShellWrapper
    copyDesktopItems
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtmultimedia
    qt6.qtsvg
    qt6.qtwayland
    gtest
    libssh
    luajit
    openssl
    pcre
    sqlite
    zlib
  ];

  # gtest_discover_tests runs the widget test programs during the build.
  preBuild = ''
    export QT_QPA_PLATFORM=offscreen
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    state=$PWD/test-state
    mkdir -p $state
    export HOME=$state
    export XDG_CONFIG_HOME=$state/config
    export XDG_DATA_HOME=$state/data
    export XDG_CACHE_HOME=$state/cache
    export QT_QPA_PLATFORM=offscreen
    ctest --output-on-failure --no-tests=error -j 1
    runHook postCheck
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "mushkin";
      desktopName = "Mushkin";
      comment = "Graphical MUD client";
      exec = "mushkin %f";
      icon = "mushkin";
      categories = [ "Network" "Game" ];
      terminal = false;
      mimeTypes = [ "application/x-mushclient-world" ];
    })
  ];

  postInstall = ''
    # The executable looks for its Lua modules in lua/ and lib/ beside
    # itself, so keep the three together outside bin/.
    runtime=$out/libexec/mushkin
    mkdir -p $runtime
    mv $out/bin/mushkin $runtime/mushkin
    cp -r lua lib $runtime/

    install -Dm644 ../resources/icons/mushkin.svg \
      $out/share/icons/hicolor/scalable/apps/mushkin.svg

    doc=$out/share/doc/mushkin
    install -Dm644 -t $doc ../LICENSE ../README.md ../THIRD_PARTY_LICENSES.md
    # THIRD_PARTY_LICENSES.md is an index; the bundled sources carry more
    # notices than it lists.
    (cd .. && find . -path ./build -prune -o -type f \
      -regextype posix-extended -regex '.*/(LICENSE|COPYING|NOTICE)(\..*)?' \
      -exec install -Dm644 {} $doc/third-party-notices/{} \;)
  '';

  dontWrapQtApps = true;
  preFixup = ''
    makeShellWrapper $out/libexec/mushkin/mushkin $out/bin/mushkin \
      --run 'export MUSHKIN_HOME="''${MUSHKIN_HOME:-''${XDG_DATA_HOME:-''${HOME:-$PWD}/.local/share}/mushkin}"' \
      "''${qtWrapperArgs[@]}"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/mushkin/mushkin
    test -f $out/libexec/mushkin/lua/fennel.lua
    test -f $out/share/applications/mushkin.desktop
    test -f $out/share/doc/mushkin/third-party-notices/external/luasec/LICENSE

    # The bundled C modules load from the installed tree.  LuaSec's ssl.so
    # exports only its submodule entry points.
    ${luajit}/bin/luajit -e "
      package.cpath = '$out/libexec/mushkin/lib/?.so;$out/libexec/mushkin/lib/?/core.so'
      for _, name in ipairs { 'socket.core', 'mime.core', 'ssl.core', 'yue', 'llthreads2' } do
        require(name)
      end"

    # There is no command-line interface: start the window off screen and
    # require it to be running, with its state directory created, when
    # stopped.
    export HOME=$TMPDIR/install-check-home
    export XDG_DATA_HOME=$HOME/data
    mkdir -p $HOME
    status=0
    QT_QPA_PLATFORM=offscreen timeout 10 $out/bin/mushkin || status=$?
    test $status = 124
    test -d $XDG_DATA_HOME/mushkin
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical MUSHclient-compatible MUD client";
    longDescription = ''
      Mushkin is a Qt MUD client compatible with much of MUSHclient's Lua
      API and world and plugin file formats.  It supports Telnet
      negotiation, MCCP, MXP, GMCP, MSP, triggers, aliases, timers, LuaJIT
      scripting and remote access over SSH.  The bundled YueScript,
      LuaSocket, LuaSec and llthreads2 modules are built from source.
      Worlds, profiles, logs, plugin data and cached MSP media live under
      MUSHKIN_HOME, by default the mushkin directory in the XDG data
      directory.  There is no command-line or headless interface.
    '';
    homepage = "https://github.com/justinpopa/mushkin";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "mushkin";
  };
}
