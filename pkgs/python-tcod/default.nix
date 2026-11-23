{ lib, python3Packages, fetchPypi, SDL2, zlib, utf8proc }:

# The SDL2 python-tcod 13.6.0 binding with its matching libtcod 1.20.1
# sources, as used by Enemy Trench.  Newer tcod releases target SDL3.
python3Packages.buildPythonPackage rec {
  pname = "tcod";
  version = "13.6.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-ivcQWVwyfw7TeqR+1w7eQEczxdlM98V2PCOOQBNvCLw=";
  };

  patches = [ ./python-tcod-sdl-variadic.patch ];

  # The sdist uses CRLF in build_sdl.py; normalize it so the parser
  # backport applies without fuzz.
  prePatch = ''
    sed -i 's/\r$//' build_sdl.py
  '';

  postPatch = ''
    # Use system zlib and utf8proc instead of the vendored copies.
    rm -r libtcod/src/vendor/zlib libtcod/src/vendor/utf8proc
    substituteInPlace build_libtcod.py \
      --replace-fail 'sources += ["libtcod/src/vendor/utf8proc/utf8proc.c"]' "" \
      --replace-fail 'sources += glob.glob("libtcod/src/vendor/zlib/*.c")' "" \
      --replace-fail 'libraries: List[str] = [*build_sdl.libraries]' \
        'libraries: List[str] = [*build_sdl.libraries, "z", "utf8proc"]'
    # isascii is hidden by -std=c99; spell out its 7-bit predicate.
    substituteInPlace libtcod/src/libtcod/renderer_xterm.c \
      --replace-fail 'isascii(ch)' '(ch >= 0 && ch <= 0x7f)'
    # glibc's termios.h now defines baud-rate macros such as B10000000,
    # colliding with this file's UTF-8 bit-pattern constants.  Rename them.
    sed -i -E 's/\bB(1[01]{7})\b/UTF8_B\1/g' libtcod/src/libtcod/renderer_xterm.c
    # Package data names notices absent from this sdist; they are
    # installed explicitly below.
    sed -i -E '/"lib\/(LIBTCOD-CREDITS.txt|LIBTCOD-LICENSE.txt|README-SDL.txt)",/d' setup.py
    # Upstream pins its build backend exactly; any current setuptools works.
    substituteInPlace pyproject.toml --replace-fail '"setuptools==60.8.2"' '"setuptools"'
    # sdl2-compat's SDL_config.h describes SDL3's build configuration with
    # flags that are not compile-time constants for the binding.  Exclude them
    # from the CFFI constant table like the other configuration flags.
    substituteInPlace build_sdl.py --replace-fail '"SDL_TRUE",' '"SDL_TRUE",
            "SDL_AUDIO_DRIVER_DUMMY", "SDL_FILESYSTEM_DUMMY", "SDL_HAPTIC_DISABLED",
            "SDL_HIDAPI_DISABLED", "SDL_JOYSTICK_DISABLED", "SDL_LOADSO_DISABLED",
            "SDL_SENSOR_DISABLED", "SDL_THREADS_DISABLED", "SDL_TIMERS_DISABLED",
            "SDL_VIDEO_DRIVER_DUMMY",'
  '';

  build-system = with python3Packages; [ setuptools wheel cffi pycparser pcpp ];
  nativeBuildInputs = [ SDL2.dev ];
  buildInputs = [ SDL2 zlib utf8proc ];
  dependencies = with python3Packages; [ cffi numpy typing-extensions ];

  # The sdist ships test data but not the Python test suite.
  doCheck = false;
  pythonImportsCheck = [ "tcod" ];

  postInstall = ''
    doc=$out/share/doc/python-tcod
    install -Dm644 LICENSE.txt $doc/LICENSE.txt
    install -Dm644 -t $doc/libtcod libtcod/LICENSE.txt libtcod/LIBTCOD-CREDITS.txt
    install -Dm644 -t $doc/vendor \
      libtcod/src/vendor/{khrplatform.h,lodepng.c,lodepng.h,stb_truetype.h}
  '';

  meta = {
    description = "SDL2 Python tcod roguelike library bindings (libtcod 1.20.1)";
    homepage = "https://github.com/libtcod/python-tcod";
    license = with lib.licenses; [ bsd2 bsd3 mit lib.licenses.zlib ];
    platforms = lib.platforms.linux;
  };
}
