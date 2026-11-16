{
  lib,
  stdenv,
  fetchurl,
  ldc,
  libarchive,
  libtcod,
  coreutils,
  runtimeShell,
  xvfb,
  xdotool,
  xwd,
}:

# libtcod is the private 1.5.1 renderer built for dwarftown
# (dwarftown.libtcod); the bundled DerelictTCOD bindings target that API.
stdenv.mkDerivation {
  pname = "infection";
  # The author labels this the 2013 7DRL, without a numbered release.
  version = "2013";

  # The author's server sends a malformed media type; this capture holds the
  # same archive as https://www.tndwolf.org/infection/infection_src.rar.
  src = fetchurl {
    name = "infection-2013-src.rar";
    url = "https://web.archive.org/web/20160809031909/http://www.tndwolf.org/infection/infection_src.rar";
    hash = "sha256-GpYGyeLkKbAq9Dixc62R6g6+SvRd79aFGETWputaEgo=";
  };

  nativeBuildInputs = [ ldc libarchive ];

  # libarchive reads RAR without unrar.  Mercurial history, archived
  # executables and Windows import libraries are never extracted.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    bsdtar -xf $src -C source \
      --exclude=.hg --exclude='.hg/*' --exclude=src/lib --exclude=src/build \
      --exclude='*.exe' --exclude='*.dll' --exclude='*.lib' --exclude='*.obj' \
      --exclude='*.o' --exclude='*.a' --exclude='*.so' --exclude='*.dylib'
    cd source
    # The author's font has two custom glyph cells; it is not the similarly
    # named libtcod sample.
    echo 'cb17ade2c0a346af0de6f5d66877d68cf2736d1689ae7bc4dc4e34382e1720ce  data/dejavu16x16_gs_tc.png' \
      | sha256sum -c -
    runHook postUnpack
  '';

  # The D sources came from a Windows working tree.
  prePatch = ''
    find src -name '*.d' -exec sed -i 's/\r//g' {} +
  '';

  # Current Phobos and druntime module paths, explicit imports and integer
  # widths for the 64-bit frontend, and missing-key reads that return zero
  # as the original catch blocks intended.
  patches = [ ./portability.patch ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  postPatch = ''
    substituteInPlace src/derelict/tcod/libtcod.d \
      --replace-fail 'enum libNames = "libtcod.so";' \
        'enum libNames = "${libtcod}/lib/libtcod.so";'
  '';

  dontConfigure = true;

  # Upstream's release mode, over the game modules and the Linux part of the
  # bundled Derelict bindings.
  buildPhase = ''
    runHook preBuild
    mkdir build
    ldc2 --gcc=$CC -release -Isrc -od=build -of=build/infection \
      src/main.d src/characters.d src/map.d src/system.d src/traits.d src/world.d \
      src/derelict/tcod/types.d src/derelict/tcod/functions.d src/derelict/tcod/libtcod.d \
      src/derelict/util/exception.d src/derelict/util/loader.d \
      src/derelict/util/sharedlib.d src/derelict/util/system.d
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/infection
    install -Dm755 -t $out/libexec build/infection
    mkdir -p $data
    cp -r data $data/data

    doc=$out/share/doc/infection
    install -Dm644 -t $doc src/license.txt
    install -Dm644 ${./font-notices.txt} $doc/infection-font-notices.txt
    install -Dm644 -t $doc ${libtcod}/share/doc/dwarftown-libtcod/*
    install -Dm644 ${libtcod.src}/data/fonts/README.txt $doc/libtcod-fonts-README.txt
    sed -n '/^Boost Software License/,/^DEALINGS IN THE SOFTWARE/p' \
      src/derelict/util/loader.d > $doc/DERELICT-LICENSE.txt
    grep -q 'Boost Software License' $doc/DERELICT-LICENSE.txt
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    Infection, Luca Carbone, 2013 Seven Day Roguelike Challenge
    Source: https://www.tndwolf.org/infection/infection_src.rar
    (SHA256 1a9606c9e2e429b02af438b173ad91ea0ebe4af45defd6851844d6a6eb5a120a)

    Game sources, data and title art: BSD-2-Clause (license.txt).
    data/dejavu16x16_gs_tc.png is the author's DejaVu-derived bitmap with two
    custom glyph cells: infection-font-notices.txt.
    Bundled DerelictTCOD and DerelictUtil bindings, compiled from source:
    Boost Software License 1.0 (DERELICT-LICENSE.txt).
    libtcod 1.5.1: the channel's source-built private library, BSD-3-Clause,
    with the zlib-licensed LodePNG codec (LIBTCOD-LICENSE.txt,
    LIBTCOD-CREDITS.txt, lodepng.c, lodepng.h).  SDL 1.2 is the Nixpkgs
    sdl12-compat layer; README-SDL.txt is the historic redistribution notice.

    The archived Windows executable, DLLs, import libraries and Mercurial
    history are not extracted.  Asset bytes are unchanged.
    EOF

    # Every read is relative to data/.  The game has no save system.
    mkdir -p $out/bin
    cat > $out/bin/infection <<EOF
    #!${runtimeShell}
    set -eu
    umask 077
    cd -- $data
    exec $out/libexec/infection "\$@"
    EOF
    chmod 555 $out/bin/infection
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb xdotool xwd ];
  installCheckPhase = ''
    runHook preInstallCheck
    export PATH=${lib.makeBinPath [ coreutils xvfb xdotool xwd ]}:$PATH
    sh ${./smoke.sh} $out
    ! find $out \( -name '*.dll' -o -name '*.exe' -o -name '*.lib' -o -name '*.so*' \) | grep -q .
    runHook postInstallCheck
  '';

  meta = {
    description = "Roguelike about a pathogen infecting a human body, from the 2013 Seven Day Roguelike Challenge";
    longDescription = ''
      Infection is Luca Carbone's 2013 Seven Day Roguelike.  Guide a pathogen
      through the body's organs, infect cornerstone cells, fight immune cells
      and buy traits with the resources you consume.  The D game and its
      bundled Derelict bindings are built from source against a private
      libtcod 1.5.1.  Both difficulty modes, the original controls, title art
      and bitmap font are kept.  The game has no save system.
    '';
    homepage = "https://www.tndwolf.org/infection/";
    license = with lib.licenses; [ bsd2 boost bsd3 zlib bitstreamVera ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "infection";
  };
}
