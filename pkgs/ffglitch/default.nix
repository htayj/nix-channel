{ lib
, stdenv
, fetchurl
, makeWrapper
, nasm
, perl
, pkg-config
, texinfo
, python3
, alsa-lib
, bzip2
, libx11
, libxcb
, libxext
, libxv
, SDL2
, xz
, zlib
}:

let
  # Native .py scripting imports NumPy; give the embedded interpreter one
  # self-contained prefix instead of the invoking user's Python setup.
  pythonEnv = python3.withPackages (ps: [ ps.numpy ]);
  libpython = "${python3}/lib/libpython${python3.pythonVersion}.so.1.0";

  configureFlags = [
    "--enable-gpl"
    "--enable-static"
    "--disable-shared"
    "--disable-stripping"
    "--enable-runtime-cpudetect"
    "--enable-ffedit"
    "--enable-ffmpeg"
    "--enable-ffplay"
    "--enable-ffprobe"
    # ZeroMQ, RtMidi, QuickJS and Xvid are modified in-tree components.
    "--enable-libzmq"
    "--enable-rtmidi"
    "--enable-sdl2"
    "--enable-alsa"
    "--enable-libxcb"
    "--enable-libxcb-shm"
    "--enable-libxcb-shape"
    "--enable-libxcb-xfixes"
    "--enable-xlib"
    # Upstream has no ffedit.texi; keep generated man pages and QuickJS docs.
    "--disable-htmlpages"
    "--disable-podpages"
  ];

  quickjsTests = [
    "test_closure.js" "test_language.js" "test_builtin.js"
    "test_loop.js" "test_std.js" "test_worker.js"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ffglitch";
  version = "0.10.2";

  # Official release of ffglitch-core 225c210d02a30949e7d0443109c4cd2a8bea94d0.
  src = fetchurl {
    url = "https://ffglitch.org/pub/src/ffglitch-${finalAttrs.version}.tar.xz";
    hash = "sha256-euy71M4bBChG5DA4votMqxZhZQUnnVMQ0z0WqkJbpG4=";
  };

  nativeBuildInputs = [ makeWrapper nasm perl pkg-config pythonEnv texinfo ];
  buildInputs = [ alsa-lib bzip2 libx11 libxcb libxext libxv SDL2 xz zlib ];

  postPatch = ''
    # Python scripting is compiled in and dlopens libpython; bind it to the
    # store path.  FFGLITCH_LIBPYTHON_PATH stays as the upstream override.
    substituteInPlace libavutil/script_python.c \
      --replace-fail '"libpython3.13.so.1"' '"${libpython}"'

    substituteInPlace libavutil/quickjs/tests/test_std.js \
      --replace-fail '"/bin/sh"' '"${stdenv.shell}"'

    # The helper still used the pre-0.10 positional ffedit command line.
    substituteInPlace ffglitch/ffglitch.py \
      --replace-fail 'ffedit_path = [os.path.join(dir_path, "ffedit")]' \
                     'ffedit_path = ["${placeholder "out"}/bin/ffedit"]' \
      --replace-fail 'run_ffedit([args.input,' 'run_ffedit(["-i", args.input,' \
      --replace-fail 'json_out, args.output]' 'json_out, "-o", args.output]' \
      --replace-fail '#!/usr/bin/env python' '#!${python3.interpreter}'

    # These three tests read vsynth_lena.yuv, generated from the external
    # SAMPLES/lena.pnm, but were registered as sample-free.
    sed -i -E \
      's/^FATE_FFMPEG-(.* \+= fate-ffmpeg-(filter-in-eof|streamcopy-t|loopback-decoding))$/FATE_SAMPLES_FFMPEG-\1/' \
      tests/fate/ffmpeg.mak
    test "$(grep -cE '^FATE_SAMPLES_FFMPEG-.*fate-ffmpeg-(filter-in-eof|streamcopy-t|loopback-decoding)$' tests/fate/ffmpeg.mak)" = 3

    # configure's TMPDIR probe writes this shebang into a generated script.
    substituteInPlace configure --replace-fail '#! /bin/sh' '#!${stdenv.shell}'
    patchShebangs configure tests/ffedit/scripts
  '';

  # FFmpeg's configure is not autoconf; pass only the options it accepts.
  configurePhase = ''
    runHook preConfigure
    export SHELL=${stdenv.shell} CONFIG_SHELL=${stdenv.shell}
    ./configure \
      --prefix=$out \
      --datadir=$out/share/ffglitch \
      --docdir=$out/share/doc/ffglitch \
      --cc=$CC --cxx=$CXX \
      ${lib.escapeShellArgs configureFlags}
    runHook postConfigure
  '';

  enableParallelBuilding = true;

  # The default target omits the standalone interpreter with MIDI/ZeroMQ modules.
  postBuild = ''
    make -j$NIX_BUILD_CORES qjs
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export PYTHONHOME=${pythonEnv}

    # Sample-free FATE suite.
    make -j$NIX_BUILD_CORES fate

    # Offline QuickJS tests, run with the qjs built above.
    (cd libavutil/quickjs
     for t in ${lib.concatStringsSep " " quickjsTests}; do
       ../../qjs tests/$t
     done)

    # The ffedit harness overwrites its expected files; keep copies and
    # compare, ignoring only the build-root "filename" lines.
    expected=$TMPDIR/ffedit-expected
    mkdir -p $expected
    cp -r tests/ffedit/ref tests/ffedit/json $expected/
    ln -s . src
    make ffedit-tests
    status=0
    for kind in ref json; do
      for f in $expected/$kind/*; do
        if ! diff <(grep -vF '"filename"' "$f") \
                  <(grep -vF '"filename"' "tests/ffedit/$kind/$(basename "$f")") >/dev/null; then
          echo "ffedit regression mismatch: $kind/$(basename "$f")"
          status=1
        fi
      done
    done
    rm src
    [ $status = 0 ]
    runHook postCheck
  '';

  # Install the fork's tools only: no stock FFmpeg names, no ABI-incompatible
  # libav* headers, libraries or pkg-config files.
  installPhase = ''
    runHook preInstall
    doc=$out/share/doc/ffglitch

    install -Dm755 -t $out/bin ffedit ffgac fflive
    install -Dm755 ffprobe $out/bin/ffglitch-ffprobe
    install -Dm755 -t $out/libexec/ffglitch qjs
    install -Dm644 -t $out/share/ffglitch ffglitch/ffglitch.js
    install -Dm755 -t $out/share/ffglitch ffglitch/ffglitch.py

    install -Dm644 -t $doc README.md INSTALL.md RELEASE_NOTES Changelog CREDITS \
      LICENSE.md COPYING.GPLv2 COPYING.GPLv3 COPYING.LGPLv2.1 COPYING.LGPLv3

    # Generic FFmpeg manuals stay private to avoid collisions with ffmpeg.
    find doc -name '*.[13]' -size +0 -exec install -Dm644 -t $doc/man {} +
    mkdir -p $doc/quickjs
    cp -r libavutil/quickjs/doc/. $doc/quickjs/

    install -Dm644 libavutil/quickjs/LICENSE $doc/licenses/quickjs/LICENSE
    install -Dm644 libavutil/zeromq/LICENSE $doc/licenses/zeromq/LICENSE
    install -Dm644 libavutil/rtmidi/LICENSE $doc/licenses/rtmidi/LICENSE
    install -Dm644 libavcodec/xvidcore/LICENSE $doc/licenses/xvidcore/LICENSE

    # Required copyright and disclaimer notices not in the license texts.
    install -Dm644 -t $doc/licenses/source-notices \
      libavutil/zeromq/external/sha1/sha1.c \
      libavutil/quickjs/quickjs-zmq.c \
      libavutil/quickjs/quickjs-rtmidi.cpp \
      libavcodec/jfdctfst.c libavcodec/jfdctint_template.c libavcodec/jrevdct.c

    cat > $doc/NOTICES <<'EOF'
    FFglitch 0.10.2 is built with GPL components, including bundled Xvid.
    FFmpeg/FFglitch code is LGPL-2.1-or-later, with GPL-2.0-or-later components.
    Bundled QuickJS and RtMidi use the Expat license; ZeroMQ uses MPL-2.0.
    ZeroMQ's bundled SHA-1 implementation uses the three-clause BSD license.
    This software is based in part on the work of the Independent JPEG Group.
    The Nix package makes no changes to the three IJG-derived source files.
    Component licenses and source copyright notices are in licenses/.

    Tools: bin/ffedit, bin/ffgac, bin/fflive, bin/ffglitch-ffprobe.
    FFglitch's standalone QuickJS: libexec/ffglitch/qjs.
    JSON JavaScript helper and media Python helper: share/ffglitch/.
    Native .py scripting loads the package's Python library by default;
    FFGLITCH_LIBPYTHON_PATH remains an explicit upstream override.
    Generic FFmpeg man pages are retained privately in this directory's man/.
    EOF

    for tool in ffedit fflive; do
      wrapProgram $out/bin/$tool --set PYTHONHOME ${pythonEnv}
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
    unset PYTHONHOME PYTHONPATH

    $out/bin/ffedit -version >/dev/null
    $out/bin/ffgac -version >/dev/null
    $out/bin/fflive -version >/dev/null
    $out/bin/ffglitch-ffprobe -version >/dev/null
    test "$($out/libexec/ffglitch/qjs -e 'console.log(6 * 7)')" = 42

    grep -aqF '${libpython}' $out/bin/.ffedit-wrapped
    test -e '${libpython}'
    grep -q '${pythonEnv}' $out/bin/ffedit
    grep -qF "\"$out/bin/ffedit\"" $out/share/ffglitch/ffglitch.py
    grep -qF '"-i", args.input' $out/share/ffglitch/ffglitch.py
    head -1 $out/share/ffglitch/ffglitch.py | grep -q '^#!/nix/store/'
    $out/share/ffglitch/ffglitch.py --help >/dev/null

    # Export and native JavaScript/Python scripting on a shipped fixture.
    fixture=tests/ffedit/src/libxvid_prepared_128_5_mv4_null.rawvideo
    $out/bin/ffedit -hide_banner -i $fixture -f mv -e $TMPDIR/mv.json
    grep -q '"mv"' $TMPDIR/mv.json
    $out/bin/ffedit -hide_banner -i $fixture -f mv \
      -s tests/ffedit/scripts/mv_sink_and_rise_mv4_python.py -o $TMPDIR/py.avi
    $out/bin/ffedit -hide_banner -i $fixture -f mv \
      -s tests/ffedit/scripts/mv_sink_and_rise_mv4_quickjs.js -o $TMPDIR/js.avi
    test -s $TMPDIR/py.avi
    test -s $TMPDIR/js.avi

    test -s $out/share/doc/ffglitch/NOTICES
    test -n "$(ls $out/share/doc/ffglitch/man)"
    test ! -e $out/lib
    test ! -e $out/include
    runHook postInstallCheck
  '';

  meta = {
    description = "FFmpeg fork for multimedia bitstream editing and live glitch scripting";
    longDescription = ''
      FFglitch edits encoded multimedia bitstreams.  It includes ffedit for
      JSON export, import and native JavaScript or Python scripting; ffgac for
      glitch-oriented encoding; and fflive for live scripted playback.  Its
      bundled QuickJS interpreter, installed as libexec/ffglitch/qjs, supports
      ZeroMQ messaging and MIDI.  The tools coexist with stock FFmpeg;
      FFglitch's ffprobe is installed as ffglitch-ffprobe.
    '';
    homepage = "https://ffglitch.org/";
    license = with lib.licenses; [ gpl2Plus lgpl21Plus mit mpl20 bsd3 ijg ];
    mainProgram = "ffedit";
    platforms = [ "x86_64-linux" ];
  };
})
