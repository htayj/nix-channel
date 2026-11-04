{ lib, stdenvNoCC, fetchFromGitHub, python3, coreutils, ttf-bitstream-vera }:

let
  python = python3.withPackages (ps: [ ps.pysdl2 ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "crashrun";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "DanaL";
    repo = "crashRun";
    rev = "9b95cc7dd2b8227a219769a95fcaee48e3371bec";
    hash = "sha256-yM9ZEACvf1N/MYsAhJGVvGv/znTeQEiaT7ANT4O1v9Y=";
  };

  nativeBuildInputs = [ python ];

  # Same source fixes as the Guix package: drop the unused Python 2-only
  # import, poll SDL events directly instead of loading sdl2.ext, and test
  # the shift modifier as a bit flag.
  postPatch = ''
    substituteInPlace crashRun.py \
      --replace-fail "from sys import setcheckinterval" ""
    substituteInPlace src/DisplayGuts.py \
      --replace-fail "import sdl2.ext as sdl2ext" "" \
      --replace-fail "events = sdl2ext.get_events()" "" \
      --replace-fail "for event in events:" "while SDL_PollEvent(ctypes.byref(event)):" \
      --replace-fail "event.key.keysym.mod in ([4097, 4098])" "event.key.keysym.mod & KMOD_SHIFT"
    if grep -rn "sdl2ext\|setcheckinterval" --include=*.py .; then
      echo "unpatched references remain" >&2; exit 1
    fi
  '';

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m py_compile crashRun.py src/*.py
    find . -name __pycache__ -type d -prune -exec rm -rf {} +
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    data=$out/share/crashrun
    doc=$out/share/doc/crashrun
    mkdir -p $data $doc $out/bin
    cp -r crashRun.py src help.txt keys.txt rumours.txt ttd.txt VeraMono.ttf $data/
    install -m644 README license.txt $doc/
    # The bundled VeraMono.ttf is unmodified Bitstream Vera Sans Mono;
    # ship its notice from the Vera release.
    tar -xjf ${ttf-bitstream-vera.src} --strip-components=1 -C $doc \
      ttf-bitstream-vera-${ttf-bitstream-vera.version}/COPYRIGHT.TXT

    cat > $out/bin/crashrun <<EOF
    #!${stdenvNoCC.shell}
    set -eu
    test "\$#" -eq 0 || { echo 'usage: crashrun' >&2; exit 64; }
    export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/crashrun"
    ${coreutils}/bin/mkdir -p "\$state"
    for resource in help.txt keys.txt rumours.txt ttd.txt VeraMono.ttf; do
      if test ! -e "\$state/\$resource"; then
        ${coreutils}/bin/cp "$data/\$resource" "\$state/\$resource"
        ${coreutils}/bin/chmod u+w "\$state/\$resource"
      fi
    done
    cd "\$state"
    export PYTHONPATH="$data"
    exec ${python.interpreter} "$data/crashRun.py"
    EOF
    chmod 555 $out/bin/crashrun
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/crashrun/VeraMono.ttf
    test -f $out/share/doc/crashrun/COPYRIGHT.TXT
    ! find $out -name __pycache__ | grep -q .
    status=0; $out/bin/crashrun extra 2>/dev/null || status=$?
    test "$status" -eq 64
    PYTHONPATH=$out/share/crashrun ${python.interpreter} -c 'import sdl2, sdl2.sdlttf'
    runHook postInstallCheck
  '';

  meta = {
    description = "Cyberpunk roguelike game written in Python with SDL2";
    homepage = "https://github.com/DanaL/crashRun";
    license = with lib.licenses; [ gpl3Plus bitstreamVera ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "crashrun";
  };
})
