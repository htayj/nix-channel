{ lib, stdenv, fetchFromGitHub, makeWrapper, swig, lua5_1, SDL, zlib, libGL, libGLU, libX11 }:

let
  # The game's SWIG interface needs the libtcod 1.5.1 C and C++ API, which
  # Nixpkgs does not package.  This build is private to the game.
  libtcod = stdenv.mkDerivation {
    pname = "dwarftown-libtcod";
    version = "1.5.1";

    # Official tag 1.5.1.
    src = fetchFromGitHub {
      owner = "libtcod";
      repo = "libtcod";
      rev = "a7cabfda0b0c770d4092f0dec02efbd2a3b6d990";
      hash = "sha256-w9BlI6xFR1fY/85/L7p+UIxmVyyMTjz7tSKcGm21esU=";
    };

    # libX11 serves the renderer's clipboard support in sys_c.c; SDL_opengl.h
    # includes GL/glu.h.
    buildInputs = [ SDL zlib libGL libGLU libX11 ];

    postPatch = ''
      # Dependencies come from Nixpkgs; archived binaries are never used.
      rm -r dependencies
      rm ascii-paint/ascii-paint-linux
      find . -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.so' \
        -o -name '*.so.*' -o -name '*.a' -o -name '*.o' \) -delete

      # These historical sources use CRLF line endings.
      sed -i 's/\r$//' src/sys_sdl_c.c src/sys_sdl_img_png.c

      # Match the three-int declaration in libtcod_int.h.
      substituteInPlace src/sys_sdl_c.c \
        --replace-fail 'TCOD_sys_map_ascii_to_font(asciiCode, fontCharX, fontCharY)' \
          'TCOD_sys_map_ascii_to_font(int asciiCode, int fontCharX, int fontCharY)'

      # TCOD_sys_read_file writes a uint32; widen it for LodePNG afterwards.
      substituteInPlace src/sys_sdl_img_png.c \
        --replace-fail $'\tsize_t pngsize;' $'\tuint32 file_size;\n\tsize_t pngsize;' \
        --replace-fail 'TCOD_sys_read_file(filename,&png,&pngsize)) return NULL;' \
          'TCOD_sys_read_file(filename,&png,&file_size)) return NULL; pngsize = file_size;'

      # Link the C++ library with the C++ driver, after the C library exists.
      substituteInPlace makefiles/makefile-linux64 \
        --replace-fail 'libtcodxx.so : ' 'libtcodxx.so : libtcod.so ' \
        --replace-fail 'gcc -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_CPP_RELEASE)' \
          '$(CPP) -shared -Wl,-soname,$@ -o $@ $(LIBOBJS_CPP_RELEASE)'
    '';

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      # The makefile's shared /tmp object directory is replaced by a local one.
      mkdir -p build-objects/libtcod/release/png
      make -f makefiles/makefile-linux64 -j$NIX_BUILD_CORES libtcod.so libtcodxx.so \
        CC="$CC -std=gnu99" CPP="$CXX -std=gnu++98" \
        TEMP="$PWD/build-objects" \
        CFLAGS="-O2 -fPIC -Iinclude -Iinclude/gui -Wall -fno-strict-aliasing -D_GNU_SOURCE=1 -D_REENTRANT -I${lib.getDev SDL}/include/SDL -Wl,-rpath,$out/lib" \
        SDL_LIBS="-lSDL -lm" ZLIB_LIBS="-lz" OPENGL_LIB="-lGL -lX11"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 -t $out/lib libtcod.so libtcodxx.so
      cp -r include $out/include
      # The embedded LodePNG codec's notice lives in its source.
      install -Dm644 -t $out/share/doc/dwarftown-libtcod \
        LIBTCOD-LICENSE.txt LIBTCOD-CREDITS.txt README-SDL.txt \
        src/png/lodepng.c src/png/lodepng.h
      runHook postInstall
    '';

    meta = {
      description = "Historical libtcod 1.5.1 renderer private to Dwarftown";
      homepage = "https://github.com/libtcod/libtcod";
      license = [ lib.licenses.bsd3 lib.licenses.zlib ];
      platforms = [ "x86_64-linux" ];
    };
  };
in
stdenv.mkDerivation {
  pname = "dwarftown";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "pwmarcz";
    repo = "dwarftown";
    rev = "9488ae4ec385459ed6c8d15a642e43c8a11607f7";
    hash = "sha256-P2GR98Mc1SzFNULisk8ja2TNQerR/bd7ao3MTSk+Msc=";
  };

  nativeBuildInputs = [ swig makeWrapper ];
  buildInputs = [ lua5_1 libtcod ];

  postPatch = ''
    # Shipped interpreters, binary modules, headers and the SWIG 1.3 wrapper
    # are never used; the module is regenerated from the interface.
    rm -r wrapper/linux wrapper/linux64 wrapper/windows wrapper/include
    rm wrapper/swig/libtcod_wrap.cxx

    # Resolve modules and the font from the store, not the caller's directory.
    # Character dumps, log.txt and screenshots still go to the working directory.
    data=$out/share/dwarftown
    substituteInPlace src/main.lua --replace-fail \
      "package.path = package.path .. ';src/?.lua;src/?/init.lua;wrapper/?.lua'" \
      "package.path = '$data/src/?.lua;$data/src/?/init.lua;$data/wrapper/?.lua'; package.cpath = '$out/lib/dwarftown/?.so'"
    substituteInPlace src/ui.lua --replace-fail \
      "'fonts/terminal10x18.png'" "'$data/fonts/terminal10x18.png'"
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # Old metatable bindings are SWIG's default; tcod.lua relies on the flat
    # TCODClass_member names.  Squash bases keeps the pre-3.0 class layout.
    # TCODLIB_API must expand to nothing (SWIG >= 4.1 makes -DFOO mean 1).
    swig -c++ -lua -squash-bases -DTCODLIB_API= \
      -I${libtcod}/include -Iwrapper/swig \
      -o wrapper/swig/libtcod_wrap.cxx wrapper/swig/libtcod.i
    $CXX -std=gnu++11 -O2 -fPIC -shared \
      -I${libtcod}/include -Iwrapper/swig \
      wrapper/swig/libtcod_wrap.cxx -o libtcodlua.so \
      -ltcodxx -ltcod -llua
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/dwarftown
    mkdir -p $data
    cp -r src fonts $data/
    install -Dm644 -t $data/wrapper wrapper/tcod.lua wrapper/terminal.png
    install -Dm755 -t $out/lib/dwarftown libtcodlua.so

    doc=$out/share/doc/dwarftown
    install -Dm644 -t $doc LICENSE.txt README.txt
    install -Dm644 wrapper/readme.txt $doc/wrapper-readme.txt
    install -Dm644 -t $doc ${libtcod}/share/doc/dwarftown-libtcod/*
    tar -xzf ${lua5_1.src} -O lua-5.1.5/COPYRIGHT > $doc/LUA-COPYRIGHT
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    Dwarftown 1.0, original 2011 Seven Day Roguelike
    ================================================
    Source: https://github.com/pwmarcz/dwarftown
    Commit: 9488ae4ec385459ed6c8d15a642e43c8a11607f7

    Game Lua code, fonts/terminal10x18.png and the SWIG interface adaptations:
    Pawel Marczewski, MIT license (LICENSE.txt).

    libtcod 1.5.1 (commit a7cabfda0b0c770d4092f0dec02efbd2a3b6d990, official tag
    1.5.1), rebuilt from source as a private shared library: BSD-3-Clause, see
    LIBTCOD-LICENSE.txt and LIBTCOD-CREDITS.txt.  wrapper/terminal.png matches
    libtcod 1.5.1 ascii-paint/terminal.png and is covered by that grant.  The
    embedded LodePNG codec is under the zlib license; its notice and complete
    source are lodepng.c and lodepng.h.

    The Lua module is regenerated with SWIG from wrapper/swig/libtcod.i,
    LuaCallbacks.hpp and BackgroundHelperFunctions.hpp.  The interpreter is the
    separate Nixpkgs Lua 5.1.5 (MIT, LUA-COPYRIGHT).  SDL 1.2 is the Nixpkgs
    sdl12-compat layer; zlib and libGL also come from Nixpkgs.  The historic
    SDL redistribution notice is kept as README-SDL.txt.

    Bundled interpreters, shared libraries, Windows binaries and the shipped
    SWIG 1.3.40 wrapper are not used.  Character dumps are text summaries, not
    resumable saves.
    EOF

    makeWrapper ${lua5_1}/bin/lua $out/bin/dwarftown \
      --add-flags $data/src/main.lua
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/config XDG_DATA_HOME=$TMPDIR/data \
      XDG_CACHE_HOME=$TMPDIR/cache XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/run
    mkdir -p $HOME $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_CACHE_HOME $XDG_STATE_HOME $XDG_RUNTIME_DIR
    export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
    data=$out/share/dwarftown

    find $data -name '*.lua' -exec ${lua5_1}/bin/luac -p {} +
    grep -qF "package.cpath = '$out/lib/dwarftown/?.so'" $data/src/main.lua
    grep -qF "$data/fonts/terminal10x18.png" $data/src/ui.lua

    # Load the module and wrapper without opening a window.
    ${lua5_1}/bin/lua -e "
      package.path = '$data/wrapper/?.lua'
      package.cpath = '$out/lib/dwarftown/?.so'
      require 'tcod'
      for _, f in ipairs { 'initRoot', 'setCustomFont', 'flush', 'waitForKeypress', 'blit', 'getRoot' } do
        assert(type(tcod.console[f]) == 'function', 'tcod.console.' .. f)
      end
      assert(type(tcod.system.saveScreenshot) == 'function', 'saveScreenshot')
      assert(tcod.color.red, 'tcod.color.red')
      assert(tcod.k.ENTER and tcod.k.KPENTER, 'tcod.k')
      assert(tcod.FOV_PERMISSIVE_8 and tcod.RENDERER_SDL and tcod.FONT_LAYOUT_ASCII_INROW
             and tcod.CENTER and tcod.BKGND_SET, 'constants')
      assert(tcod.Console and tcod.Map and tcod.Path and tcod.path.Callback
             and tcod.Random and tcod.Image, 'classes')
      assert(type(getmetatable(libtcodlua)['.get'].TCODConsole_root) == 'function', 'root getter')
    "
    ! find $out \( -name '*.dll' -o -name '*.exe' -o -name 'liblua*' \) | grep -q .
    runHook postInstallCheck
  '';

  meta = {
    description = "Original Dwarftown roguelike from the 2011 Seven Day Roguelike Challenge";
    longDescription = ''
      Dwarftown is Pawel Marczewski's 2011 Seven Day Roguelike, written in Lua.
      Its Lua 5.1 SWIG module and a private libtcod 1.5.1 renderer are built
      from source.  The original 80 by 25 console, 10 by 18 font and keyboard
      controls are kept.  Character dumps, error logs and screenshots are
      written to the current working directory.
    '';
    homepage = "https://pwmarcz.pl/dwarftown/";
    license = [ lib.licenses.mit lib.licenses.bsd3 lib.licenses.zlib ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "dwarftown";
  };
}
