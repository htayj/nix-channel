{
  lib,
  stdenv,
  fetchurl,
  cmake,
  pkg-config,
  perl,
  boost,
  python312,
  SDL2,
  SDL2_image,
  libGL,
  libpng,
  zlib,
  fontconfig,
  catch2_3,
  coreutils,
  runtimeShell,
  xvfb,
  xdotool,
  xwd,
  imagemagick,
}:

let
  python = python312;
  # Boost.Python must be built against the interpreter the game embeds.
  boostPython = boost.override {
    enablePython = true;
    inherit python;
  };

  notice = name: url: hash: fetchurl { inherit name url hash; };
  notices = {
    cpython = notice "CPython-3.11-LICENSE.txt"
      "https://raw.githubusercontent.com/python/cpython/v3.11.9/LICENSE"
      "sha256-Oy+B/iHRgcSZxZolbI4ZaEVdZonSaaqFNzv7avQdo78=";
    libtcod151 = notice "libtcod-1.5.1-LICENSE.txt"
      "https://raw.githubusercontent.com/libtcod/libtcod/1.5.1/LIBTCOD-LICENSE.txt"
      "sha256-jTADNnIeUdXj9urORnlInlWMAzU2v9UkuzXDciXKLog=";
    libtcodFonts = notice "libtcod-1.5.1-fonts-README.txt"
      "https://raw.githubusercontent.com/libtcod/libtcod/1.5.1/data/fonts/README.txt"
      "sha256-Z2qcS7gdA8/RPVqj1chap1+VSoApJowInyLclSFDW/A=";
    libtappp = notice "libtappp-LICENSE.txt"
      "https://raw.githubusercontent.com/Leont/libtap--/0c5d8cb04321ff6fd98da675dfb2d1a02ac69d09/LICENSE"
      "sha256-oY8qGzSf+J0QVJcBf8+/OE3XNQT1E+/QH4T9RV8UG8o=";
    cmake = notice "CMake-2.8.12-Copyright.txt"
      "https://raw.githubusercontent.com/Kitware/CMake/v2.8.12/Copyright.txt"
      "sha256-gH6YC2juxlzCP3nutbuhOuWIq/J3kPBQFv2HSUMnSRM=";
    pefile = notice "pefile-COPYING.txt"
      "https://raw.githubusercontent.com/erocarrera/pefile/0765430d39cb1f0e5b109665b71f556dd25ecbc2/COPYING"
      "sha256-JJbt1InQcSOZq9HF5yeZuaBXiK0jyfvftqU6OPGm3ug=";
    glad = notice "GLAD-0.1.28-LICENSE.txt"
      "https://raw.githubusercontent.com/Dav1dde/glad/v0.1.28/LICENSE"
      "sha256-oqiDmdTvHKtgq81t29MBtFNdEM8FHpQO3zXYZldJ+0U=";
    stb = notice "stb-LICENSE.txt"
      "https://raw.githubusercontent.com/nothings/stb/2e2bef463a5b53ddf8bb788e25da6b8506314c08/LICENSE"
      "sha256-vr/pBLFDAWV+Tl1lXIEdUf0xuXxFW5zC2GANa6xs/2M=";
  };

  # Nixpkgs removed libtcod in 2025.  1.23.1 turns TCOD_RENDERER_SDL into an
  # alias for the accelerated renderer; the game uses the original SDL2
  # software renderer, so keep 1.23.0 private to this package.
  libtcod = stdenv.mkDerivation {
    pname = "libtcod-goblins-lot";
    version = "1.23.0";

    src = fetchurl {
      name = "libtcod-8fa20ee7a7b0a84e029aa743245a3030d6c19a1d.tar.gz";
      url = "https://codeload.github.com/libtcod/libtcod/tar.gz/8fa20ee7a7b0a84e029aa743245a3030d6c19a1d";
      hash = "sha256-gByXrGazYQHSAb1WKAAb4Eely9h8RbA3DFuLLIxqd10=";
    };

    postPatch = ''
      # zlib comes from Nixpkgs; the bundled copy must not be compiled.
      rm -r src/vendor/zlib
      substituteInPlace src/libtcod/tileset_fallback.c \
        --replace-fail 'popen("fc-match' 'popen("${lib.getExe' fontconfig "fc-match"}'
      # glibc 2.42 defines B10000000 as a termios baud rate macro, which
      # breaks the UTF-8 bit-mask constants of the same names.
      sed -i -E 's/\<B(1[01]{7})\>/UTF8_MASK_\1/g' src/libtcod/renderer_xterm.c
      grep -q UTF8_MASK_10000000 src/libtcod/renderer_xterm.c
    '';

    nativeBuildInputs = [ cmake pkg-config ];
    buildInputs = [ SDL2 zlib ];
    checkInputs = [ catch2_3 ];

    # An empty toolchain file keeps CMake away from the (empty) vcpkg tree.
    # LodePNG, utf8proc, stb and the generated GLAD loader are compiled from
    # the upstream source tree; Nixpkgs has no LodePNG and libtcod's stb and
    # GLAD integration expects these exact files.
    cmakeFlags = [
      "-DCMAKE_TOOLCHAIN_FILE="
      "-DBUILD_SHARED_LIBS=ON"
      "-DLIBTCOD_TESTS=ON"
      "-DLIBTCOD_THREADS=ON"
      "-DLIBTCOD_SDL2=find_package"
      "-DLIBTCOD_ZLIB=find_package"
      "-DLIBTCOD_GLAD=vendored"
      "-DLIBTCOD_LODEPNG=vendored"
      "-DLIBTCOD_UTF8PROC=vendored"
      "-DLIBTCOD_STB=vendored"
    ];

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      cp -r ../data data
      HOME=$PWD XDG_RUNTIME_DIR=$PWD LD_LIBRARY_PATH=$PWD/bin \
        bin/unittest '~[!nonportable]'
      runHook postCheck
    '';

    postInstall = ''
      doc=$out/share/doc/libtcod-goblins-lot
      install -Dm644 ../LICENSE.txt ../LIBTCOD-CREDITS.txt -t $doc
      install -Dm644 ${notices.glad} $doc/GLAD-LICENSE.txt
      install -Dm644 ${notices.stb} $doc/stb-LICENSE.txt
      for f in glad.h khrplatform.h lodepng.h stb_ds.h stb_truetype.h utf8proc/utf8proc.h; do
        install -Dm644 ../src/vendor/$f $doc/vendor/$(basename $f)
      done
    '';

    meta = {
      description = "libtcod 1.23.0 with the original SDL2 renderer, for Goblins' Lot";
      homepage = "https://github.com/libtcod/libtcod";
      license = [ lib.licenses.bsd3 lib.licenses.mit lib.licenses.zlib lib.licenses.unlicense ];
      platforms = [ "x86_64-linux" ];
    };
  };
in
stdenv.mkDerivation {
  pname = "goblins-lot";
  version = "0.25-unstable-2025-12-13";

  # Upstream calls this snapshot 0.25dev.  The flat hash pins GitLab's
  # generated archive bytes, the same bytes Guix records.
  src = fetchurl {
    name = "goblins-lot-497febbb3d1c807d475b7ba5299cb4527d5f8bd3.tar.gz";
    url = "https://gitlab.com/api/v4/projects/12852178/repository/archive.tar.gz?sha=497febbb3d1c807d475b7ba5299cb4527d5f8bd3";
    hash = "sha256-iwZyY637dZkKbN0rqEETCCk20CMvYFJfOCMTLpYRETs=";
  };

  patches = [
    ./native-paths.patch
    ./format-security.patch
  ];

  postPatch = ''
    # Windows installer redistributables and the .NET crash reporter are
    # prebuilt PE files unused by the native build.
    rm -r tools/installer/redists game/crash-reporter/prebuilt
    rm game/crash-reporter/ICSharpCode.SharpZipLib.dll
  '';

  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [
    boostPython
    python
    SDL2
    SDL2_image
    libGL
    libpng
    zlib
    libtcod
  ];
  nativeCheckInputs = [ perl ];

  # The binary finds its data at ../share/games/goblins-lot, so it lives in
  # libexec next to bin, where a launcher validates the state directory.
  cmakeFlags = [
    "-DCMAKE_CXX_STANDARD=17"
    "-DUSE_THREADS=ON"
    "-DGOBLIN_CAMP_BINDIR=${placeholder "out"}/libexec"
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cmake --build . --target build-test
    cmake --build . --target test
    runHook postCheck
  '';

  postInstall = ''
    # The game keeps config, log, saves and mods in $XDG_CONFIG_HOME/goblins-lot
    # or ~/.config/goblins-lot.  Relative or store locations would put state
    # under the caller's directory or the store, so refuse them.
    mkdir -p $out/bin
    cat > $out/bin/goblins-lot <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    if [ -n "\''${XDG_CONFIG_HOME-}" ]; then
      config_home=\$XDG_CONFIG_HOME
    else
      unset XDG_CONFIG_HOME
      config_home=\''${HOME:?goblins-lot: HOME or XDG_CONFIG_HOME must be set}/.config
    fi
    case \$config_home in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo "goblins-lot: config directory must be outside the store: \$config_home" >&2; exit 1 ;;
      /*) ;;
      *) echo "goblins-lot: config directory must be absolute: \$config_home" >&2; exit 1 ;;
    esac
    state=\$(${coreutils}/bin/realpath -m -- "\$config_home/goblins-lot")
    case \$state in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo "goblins-lot: resolved config directory is in the store: \$state" >&2; exit 1 ;;
    esac
    exec $out/libexec/goblins-lot "\$@"
    EOF
    chmod 555 $out/bin/goblins-lot
    substituteInPlace $out/share/applications/goblins-lot.desktop \
      --replace-fail Exec=goblins-lot Exec=$out/bin/goblins-lot

    doc=$out/share/doc/goblins-lot
    install -Dm644 ../COPYING.txt ../README.md ../CHANGELOG.md -t $doc
    install -Dm644 ../game/Readme.md $doc/game-Readme.md
    install -Dm644 ../game/include/Color.hpp $doc/Color.hpp
    install -Dm644 ${notices.cpython} $doc/CPython-3.11-LICENSE.txt
    install -Dm644 ${notices.libtcod151} $doc/libtcod-1.5.1-LICENSE.txt
    install -Dm644 ${notices.libtcodFonts} $doc/libtcod-1.5.1-fonts-README.txt
    install -Dm644 ${notices.libtappp} $doc/libtappp-LICENSE.txt
    install -Dm644 ${notices.cmake} $doc/CMake-Copyright.txt
    install -Dm644 ${notices.pefile} $doc/pefile-COPYING.txt
    cat > $doc/NOTICE <<'EOF'
    Goblins' Lot (the original Goblin Camp by Ilkka Halila, continued by
    Nikolay Shaplov), GitLab dhyannataraj/goblins-lot commit
    497febbb3d1c807d475b7ba5299cb4527d5f8bd3 (0.25dev).

    Code: GPL-3.0-or-later (COPYING.txt).  Original art and data: GPLv3, by
    the original author's game-wide grant.  game/include/Color.hpp carries
    libtcod's BSD-3-Clause colour table (Color.hpp, libtcod-1.5.1-LICENSE.txt).
    gcamp/utils.py load_package is adapted from CPython 3.11 Lib/imp.py
    (CPython-3.11-LICENSE.txt).  Tiles from the crawl-tiles Oct-5-2010
    collection are CC0-1.0.  terminal.png derives from libtcod 1.5.1
    ascii-paint/terminal.png (libtcod-1.5.1-LICENSE.txt and fonts README).
    Source-only components: t/libtappp (MIT, libtappp-LICENSE.txt),
    cmake/FindSDL2*.cmake (CMake BSD, CMake-Copyright.txt), tools/pefile.py
    (BSD-3-Clause, pefile-COPYING.txt).

    Packaging: prebuilt Windows redistributables and crash-reporter binaries
    are removed before the build.  native-paths.patch fixes the XDG config
    directory typo, installs the pixmap under the prefix, drops the compiled
    Boost.System requirement and uses Python's dynamic zlib extension.
    format-security.patch prints non-literal text through "%s".
    libtcod is a private 1.23.0 build; see its share/doc directory.
    EOF
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb xdotool xwd imagemagick ];
  installCheckPhase = ''
    runHook preInstallCheck
    ! find $out -iname '*.exe' -o -iname '*.dll' | grep -q .
    export PATH=${lib.makeBinPath [ coreutils xvfb xdotool xwd imagemagick ]}:$PATH
    sh ${./smoke.sh} $out
    runHook postInstallCheck
  '';

  passthru = { inherit libtcod; };

  meta = {
    description = "Goblins' Lot, the continuation of the original Goblin Camp";
    longDescription = ''
      Goblins' Lot continues Ilkka Halila's original Goblin Camp colony
      simulation: manage goblins and orcs, designate construction and
      stockpiles, and survive in a generated world.  It includes the ASCII
      display, both original tilesets and the embedded Python scripting.
      Configuration, log and saves live in $XDG_CONFIG_HOME/goblins-lot,
      falling back to ~/.config/goblins-lot.
    '';
    homepage = "https://gitlab.com/dhyannataraj/goblins-lot";
    license = with lib.licenses; [ gpl3Only gpl3Plus bsd3 psfl cc0 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "goblins-lot";
  };
}
