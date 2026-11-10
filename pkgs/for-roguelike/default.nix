{
  lib,
  stdenv,
  fetchurl,
  boost,
  xercesc,
  libtcod,
  coreutils,
  runtimeShell,
  xvfb,
  xdotool,
}:

# libtcod is the private 1.5.1 renderer built for dwarftown
# (dwarftown.libtcod); FOR needs that historical C++ API.
let
  # Upstream states GPL-3.0-or-later in its file headers but ships a GPL-2
  # text as LICENSE; install the operative licence text too.
  gpl3 = fetchurl {
    name = "gpl-3.0.txt";
    url = "https://www.gnu.org/licenses/gpl-3.0.txt";
    hash = "sha256-OXLcl0T2SZ8Pmy2/dmlvKuetivmyPd5m1q+Gyd+zaYY=";
  };
in
stdenv.mkDerivation {
  pname = "for-roguelike";
  version = "0.1alpha-0.6ce29fb";

  # github.com/lcarst/for is gone.  Software Heritage archived master,
  # commit 6ce29fb0d9ebb020c12264630a828ec205a31362 (2014-04-22), as
  # swh:1:dir:67ae1e5002b1bc69f97a8fe4e1fd2736374356ae.  The hash pins the
  # vault's cooked tarball bytes, the same bytes Guix records.
  src = fetchurl {
    name = "for-6ce29fb0d9ebb020c12264630a828ec205a31362.tar.gz";
    url = "https://archive.softwareheritage.org/api/1/vault/flat/swh:1:dir:67ae1e5002b1bc69f97a8fe4e1fd2736374356ae/raw/";
    hash = "sha256-dtDbuvlHJjWEcBk8tpjL7Y56I7XtEoXDWW8S+B6+ZKs=";
  };

  # SDL_main becomes main, two qualified constructor names in new
  # expressions are fixed, and Path.h includes the existing Utils.h.
  patches = [ ./portability.patch ];

  buildInputs = [ boost xercesc libtcod ];

  postPatch = ''
    # Prebuilt executables and the macOS SDL framework are never used.
    rm deps/libtcod-1.5.1/{hmtool,samples_c,samples_c_debug,samples_cpp,samples_cpp_debug}
    rm build/osx/FOR/build/Debug/for
    rm -r deps/libsdl/SDL.framework

    # Read immutable assets from the store; the debug dumps stay relative
    # to the private state directory the launcher enters.
    data=$out/share/for-roguelike
    substituteInPlace src/Gui.cpp \
      --replace-fail '"data/tileset.cfg"' "\"$data/data/tileset.cfg\"" \
      --replace-fail '"font.png"' "\"$data/font.png\""
    substituteInPlace src/Debug.cpp \
      --replace-fail '"data/items.cfg"' "\"$data/data/items.cfg\""

    # Parser error callbacks pass the message as a printf format string.
    for f in src/ItemParser.cpp src/TileSetParser.cpp; do
      substituteInPlace $f --replace-fail 'printf(msg);' 'fputs(msg, stdout);'
    done
  '';

  dontConfigure = true;

  # The upstream Linux Makefile lists files that no longer exist; compile
  # every game source plus the bundled libnoise and noiseutils sources.
  buildPhase = ''
    runHook preBuild
    sources=$(find src deps/libnoisesrc-1.0.0/noise/src -name '*.cpp' -not -path '*/win32/*' | sort)
    sources="$sources deps/noiseutils/noiseutils.cpp"
    mkdir objects
    for s in $sources; do
      echo "$s"
    done | xargs -P "$NIX_BUILD_CORES" -I{} sh -c '
      o=objects/$(echo {} | tr / _).o
      $CXX -std=gnu++11 -O2 -DLINUX -Isrc -Ideps/noiseutils \
        -Ideps/libnoiseheaders-1.0.0/include -I${libtcod}/include \
        -c {} -o "$o"'
    $CXX -o for-roguelike objects/*.o \
      -L${libtcod}/lib -Wl,-rpath,${libtcod}/lib \
      -ltcodxx -ltcod -lxerces-c -lboost_random -lboost_serialization -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/for-roguelike
    install -Dm755 for-roguelike $out/libexec/for-roguelike/for-roguelike
    install -Dm644 -t $data bin/font.png
    cp -r bin/data $data/data

    doc=$out/share/doc/for-roguelike
    install -Dm644 -t $doc LICENSE README.md CHANGES TODO
    cp -r meta $doc/meta
    install -Dm644 ${gpl3} $doc/GPL-3.txt
    install -Dm644 ${./font-license.txt} $doc/font-license.txt
    install -Dm644 deps/libnoisesrc-1.0.0/COPYING.txt $doc/libnoise-COPYING.txt
    install -Dm644 deps/noiseutils/COPYING.txt $doc/noiseutils-COPYING.txt
    install -Dm644 deps/libtcod-1.5.1/data/fonts/README.txt $doc/libtcod-fonts-README.txt
    for f in LIBTCOD-LICENSE.txt LIBTCOD-CREDITS.txt; do
      install -Dm644 deps/libtcod-1.5.1/$f $doc/bundled-$f
    done
    install -Dm644 -t $doc ${libtcod}/share/doc/dwarftown-libtcod/*
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    FOR (A Fallout-like Roguelike), Lasse Carstensen, unfinished 2014 alpha
    Source: Software Heritage swh:1:rev:6ce29fb0d9ebb020c12264630a828ec205a31362
    (formerly https://github.com/lcarst/for)

    Game sources: GPL-3.0-or-later per their file headers (GPL-3.txt).  The
    upstream LICENSE file is a GPL-2 text and is installed unchanged.
    libnoise 1.0.0 and noiseutils (Jason Bevins), compiled from the bundled
    sources: LGPL-2.1-or-later (libnoise-COPYING.txt, noiseutils-COPYING.txt).
    libtcod 1.5.1: the channel's source-built private library, BSD-3-Clause,
    with the zlib-licensed LodePNG codec (lodepng.c, lodepng.h).
    font.png is byte-identical to libtcod 1.5.1 dejavu_wide16x16_gs_tc.png,
    a DejaVu raster; see font-license.txt for the Bitstream Vera and Arev
    terms.  Boost and Xerces-C come from Nixpkgs.  Bundled SDL, Xerces-C and
    prebuilt binaries are not used.
    EOF

    # The game writes leveldump.txt, visdump.txt, edgedump.txt and
    # pathdump.txt to its working directory at every start.
    mkdir -p $out/bin
    cat > $out/bin/for-roguelike <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    state_home=\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}
    case \$state_home in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo "for-roguelike: state directory must be outside the store: \$state_home" >&2; exit 1 ;;
      /*) ;;
      *) echo "for-roguelike: state directory must be absolute: \$state_home" >&2; exit 1 ;;
    esac
    state=\$(${coreutils}/bin/realpath -m -- "\$state_home/for-roguelike")
    case \$state in
      ${builtins.storeDir}|${builtins.storeDir}/*)
        echo "for-roguelike: resolved state directory is in the store: \$state" >&2; exit 1 ;;
    esac
    ${coreutils}/bin/mkdir -p -m 700 -- "\$state"
    cd -- "\$state"
    exec $out/libexec/for-roguelike/for-roguelike "\$@"
    EOF
    chmod 555 $out/bin/for-roguelike
    install -Dm755 ${./smoke.sh} $out/libexec/for-roguelike/smoke.sh
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb xdotool ];
  installCheckPhase = ''
    runHook preInstallCheck
    export PATH=${lib.makeBinPath [ coreutils xvfb xdotool ]}:$PATH
    sh $out/libexec/for-roguelike/smoke.sh $out
    ! find $out -name '*.so*' -o -name '*.dylib' | grep -q .
    runHook postInstallCheck
  '';

  meta = {
    description = "Unfinished Fallout-like roguelike alpha by Lasse Carstensen";
    longDescription = ''
      FOR is the 2014 alpha of a Fallout-like roguelike written in C++ with
      libtcod.  At start it generates a 70 by 70 Junktown level and shows it
      in a 100 by 60 cell window; arrow keys move and Escape quits.  Saving is
      not implemented.  Debug map dumps are written to
      $XDG_STATE_HOME/for-roguelike, falling back to
      ~/.local/state/for-roguelike.
    '';
    homepage = "https://www.roguebasin.com/index.php/FOR";
    license = with lib.licenses; [ gpl3Plus lgpl21Plus bsd3 zlib bitstreamVera ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "for-roguelike";
  };
}
