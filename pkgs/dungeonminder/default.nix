{ lib, stdenv, fetchurl, fetchFromGitHub, SDL, libpng, zlib, xvfb, xdotool }:

let
  # The game is written against the libtcod 1.4.0 C++ API, which Nixpkgs does
  # not package.  This build is private to the game.
  libtcod = stdenv.mkDerivation {
    pname = "dungeonminder-libtcod";
    version = "1.4.0";

    # Official tag 1.4.0.
    src = fetchFromGitHub {
      owner = "libtcod";
      repo = "libtcod";
      rev = "9ac2a3a526e7cefe8b7b330e37619bb1c4b6fb96";
      hash = "sha256-eJGUNNSlqPnKU0A5uZiuNFIXik0vtjTAeh3f6MQwa3s=";
    };

    # Current libpng accessors, pointer-sized list slots in the pathfinding
    # heap, and an explicit prototype for the glyph mapper.
    patches = [ ./libtcod-portability.patch ];

    buildInputs = [ SDL libpng zlib ];

    postPatch = ''
      # Dependencies come from Nixpkgs; archived binaries are never used.
      rm libSDL.so SDL.dll zlib1.dll

      # Link each library with its own driver, the C++ one after the C one.
      substituteInPlace makefile-linux-nodeps \
        --replace-fail 'libtcod++.so : $(TEMP)/libtcod' 'libtcod++.so : libtcod.so $(TEMP)/libtcod' \
        --replace-fail 'gcc -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_C)' \
          '$(CC) -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_C)' \
        --replace-fail 'gcc -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_CPP)' \
          '$(CPP) -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_CPP)'
    '';

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      # The makefile's shared /tmp object directory is replaced by a local one.
      mkdir -p build-objects/libtcod
      make -f makefile-linux-nodeps -j$NIX_BUILD_CORES libtcod.so libtcod++.so \
        CC="$CC -std=gnu99" CPP="$CXX -std=gnu++98" \
        TEMP="$PWD/build-objects" \
        CFLAGS="-O2 -fPIC -Iinclude -Wall -fno-strict-aliasing -D_GNU_SOURCE=1 -D_REENTRANT" \
        SDL_LIBS="-lSDL -lm" PNG_LIBS="-lpng" ZLIB_LIBS="-lz"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 -t $out/lib libtcod.so libtcod++.so
      cp -r include $out/include
      install -Dm644 -t $out/share/dungeonminder-libtcod terminal.png
      doc=$out/share/doc/dungeonminder-libtcod
      install -Dm644 -t $doc LIBTCOD-LICENSE.txt LIBTCOD-CREDITS.txt README-SDL.txt
      install -Dm644 fonts/README.txt $doc/libtcod-fonts-README.txt
      runHook postInstall
    '';

    meta = {
      description = "Historical libtcod 1.4.0 renderer private to DungeonMinder";
      homepage = "https://github.com/libtcod/libtcod";
      license = lib.licenses.bsd3;
      platforms = [ "x86_64-linux" ];
    };
  };

  # Official Linux release.  Only its licence, readme and changelog are
  # installed; its prebuilt game and libraries are never unpacked.
  release = fetchurl {
    name = "dungeonminder-0.8-linux.tar.bz2";
    url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/dungeonminder/DungeonMinder%20v0.8%20-%20Linux.tar.bz2";
    hash = "sha256-1X5xnTO03TT9Xp0Y8dIiBRADOy4rvQngEG1eT9bcEkI=";
  };
in
stdenv.mkDerivation {
  pname = "dungeonminder";
  version = "0.8";

  # Upstream publishes the game as one C++ translation unit.
  src = fetchurl {
    url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/dungeonminder/DungeonMinder.cpp";
    hash = "sha256-cGdKgxpnpKer5hF09eDa76mzoOhaZ7XkJ0l905X0ImA=";
  };

  # The archived source has CRLF line endings.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tr -d '\r' < $src > source/DungeonMinder.cpp
    runHook postUnpack
  '';
  sourceRoot = "source";

  # Standard headers for printf and exit, the unqualified TCODPath
  # constructor, and the font loaded from DUNGEONMINDER_FONT.
  patches = [ ./source-portability.patch ];

  buildInputs = [ libtcod ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CXX -std=gnu++98 -O2 -Wall -I${libtcod}/include \
      -DDUNGEONMINDER_FONT="\"$out/share/dungeonminder/terminal.png\"" \
      DungeonMinder.cpp -o dungeonminder \
      -L${libtcod}/lib -Wl,-rpath,${libtcod}/lib -ltcod++ -ltcod -lm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin dungeonminder
    font=${libtcod}/share/dungeonminder-libtcod/terminal.png
    install -Dm644 -t $out/share/dungeonminder $font

    doc=$out/share/doc/dungeonminder
    mkdir -p $doc
    for f in license readme changelog; do
      tar -xjf ${release} -O "DungeonMinder $f.txt" > $doc/$f.txt
    done
    # The release ships the same font as libtcod 1.4.0.
    tar -xjf ${release} -O terminal.png | cmp - $font
    install -Dm644 -t $doc ${libtcod}/share/doc/dungeonminder-libtcod/*
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    DungeonMinder 0.8, 2009 Seven Day Roguelike by Adam Gatt
    =========================================================
    Source: DungeonMinder.cpp from the Google Code archive of the project,
    https://code.google.com/archive/p/dungeonminder/

    The game is under Adam Gatt's permissive notice, license.txt, taken with
    readme.txt and changelog.txt from the official "DungeonMinder v0.8 -
    Linux" release.  The prebuilt game and libraries in that release are not
    used.

    libtcod 1.4.0 (commit 9ac2a3a526e7cefe8b7b330e37619bb1c4b6fb96, official
    tag 1.4.0), rebuilt from source as a private shared library: BSD-3-Clause,
    see LIBTCOD-LICENSE.txt and LIBTCOD-CREDITS.txt.

    share/dungeonminder/terminal.png is the root terminal.png of libtcod 1.4.0
    and is byte-identical to the one in the official release.  It is the 8 by
    8 pixel non-antialiased terminal font described in
    libtcod-fonts-README.txt, in standard ASCII column layout.  The libtcod
    source carries no separate notice for it.

    SDL 1.2 is the Nixpkgs sdl12-compat layer; libpng and zlib also come from
    Nixpkgs.  The historic SDL redistribution notice is kept as README-SDL.txt.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb xdotool ];
  installCheckPhase = ''
    runHook preInstallCheck
    sh ${./smoke.sh} $out
    ! find $out \( -name '*.dll' -o -name '*.exe' -o -name '*.so*' \) | grep -q .
    runHook postInstallCheck
  '';

  meta = {
    description = "Reverse roguelike about keeping an autonomous hero alive with spells";
    longDescription = ''
      DungeonMinder is Adam Gatt's 2009 Seven Day Roguelike.  An autonomous
      hero explores and fights through ten dungeon levels; the player follows
      as an invisible sprite and casts spells from three schools on the hero,
      the monsters and the terrain.  The original C++ game and a private
      libtcod 1.4.0 renderer are built from source.  The original font,
      keyboard controls and 80 by 60 cell display are kept.  The game has no
      saved games; libtcod writes screenshots to the current working
      directory.
    '';
    homepage = "https://code.google.com/archive/p/dungeonminder/";
    # The game's notice is BSD-style, but its third clause permits
    # endorsement use of the author's name; installed as
    # share/doc/dungeonminder/license.txt.  libtcod is BSD-3-Clause.
    license = [
      {
        fullName = "DungeonMinder license (BSD-style permissive notice by Adam Gatt)";
        free = true;
        redistributable = true;
      }
      lib.licenses.bsd3
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeonminder";
  };
}
