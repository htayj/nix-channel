{
  lib,
  stdenv,
  fetchFromGitHub,
  fpc,
  lua5_1,
  ncurses,
  libx11,
  coreutils,
  runtimeShell,
  util-linux,
}:

let
  # The FPC Valkyrie library has no releases; this is the commit the 0.10.11
  # tag of DRL was built against.
  fpcvalkyrie = fetchFromGitHub {
    owner = "ChaosForge";
    repo = "fpcvalkyrie";
    rev = "f89735a741a968997656c2d48a003ec569db7f22";
    hash = "sha256-bzZq0VUGKdMpEUvibWwrDP4/N2UiM7ZD5QxXcD7iTUQ=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "drl";
  version = "0.10.11";

  src = fetchFromGitHub {
    owner = "chaosforgeorg";
    repo = "drl";
    # Tag 0_10_11.
    rev = "90b797888be2550454b2b4b7d0df6aa9ef5b71ac";
    hash = "sha256-Pjtx7w5uExJNDHWr5eYZB7cnedRRUR+XKuG9x6Evv+0=";
    # ext holds prebuilt FMOD, Steam and SDL libraries.
    postFetch = ''
      rm -r $out/ext
    '';
  };

  postPatch = ''
    cp -r ${fpcvalkyrie} fpcvalkyrie
    chmod -R u+w fpcvalkyrie

    # makefile.lua reads its platform and library location from this file.
    cat > config.lua <<'EOF'
    OS = "LINUX"
    VALKYRIE_ROOT = "fpcvalkyrie/"
    EOF

    # Load Lua at run time instead of linking lua5.1.a, and let the linker
    # and the executable find the libraries of the curses and SDL units.
    substituteInPlace makefile.lua --replace-fail \
      '"-Fu"..VALKYRIE_ROOT.."libs",' \
      '"-Fu"..VALKYRIE_ROOT.."libs", "-dLUA_DYNAMIC", "-Fl${ncurses}/lib", "-Fl${libx11}/lib", "-k-rpath=${ncurses}/lib", "-k-rpath=${libx11}/lib",'
    substituteInPlace fpcvalkyrie/libs/vlualibrary.pas --replace-fail \
      "LuaDefaultPath = 'lua5.1.so';" \
      "LuaDefaultPath = '${lua5_1}/lib/liblua.so.5.1';"

    # The log header otherwise records the build time.
    substituteInPlace fpcvalkyrie/src/vlog.pas \
      --replace-fail '{$I %TIME%}' "'00:00:00'" \
      --replace-fail '{$I %DATE%}' "'1970-01-01'"
  '';

  nativeBuildInputs = [
    fpc
    lua5_1
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir tmp
    lua makefile.lua
    test -x bin/drl
    runHook postBuild
  '';

  # This is the console game: the tile graphics, fonts and sound are left
  # out.  The game reads settings.lua from its working directory, so the
  # launcher runs it in the state directory.  A config.lua placed there
  # replaces the packaged one.
  installPhase = ''
    runHook preInstall

    data=$out/share/drl
    doc=$out/share/doc/drl

    install -Dm755 bin/drl $out/libexec/drl/drl

    mkdir -p $data/data
    cp -r bin/data/core bin/data/drl $data/data/
    rm -r $data/data/drl/graphics $data/data/drl/fonts
    install -Dm644 -t $data bin/config.lua

    install -Dm644 -t $doc README.md LICENSE bin/manual.txt bin/version.txt \
      bin/version_api.txt
    install -Dm644 fpcvalkyrie/LICENSE $doc/FPCVALKYRIE-LICENSE

    # The Free Pascal runtime is linked into drl: ship its Library GPL and
    # linking exception from the compiler's source.
    mkdir -p $doc/fpc-rtl
    tar -xzf ${fpc.src} -C $doc/fpc-rtl --strip-components=1 \
      fpcbuild-${fpc.version}/install/doc/COPYING \
      fpcbuild-${fpc.version}/fpcsrc/rtl/COPYING.FPC
    mv $doc/fpc-rtl/install/doc/COPYING $doc/fpc-rtl/fpcsrc/rtl/COPYING.FPC $doc/fpc-rtl/
    rm -r $doc/fpc-rtl/install $doc/fpc-rtl/fpcsrc

    mkdir -p $out/bin
    cat > $out/bin/drl <<EOF
    #!${runtimeShell}
    set -eu
    case "\''${XDG_STATE_HOME:-}" in
      /*) state=\$XDG_STATE_HOME/drl ;;
      *) state=\''${HOME:?HOME must be set}/.local/state/drl ;;
    esac
    ${coreutils}/bin/mkdir -p -- "\$state"
    cd "\$state"
    config=$data/config.lua
    if [ -f config.lua ]; then
      config=\$state/config.lua
    fi
    exec $out/libexec/drl/drl "\$@" -datapath $data/ -config "\$config" \\
      -writepath "\$state/" -scorepath "\$state/" -console -nosound -module drl
    EOF
    chmod 555 $out/bin/drl

    runHook postInstall
  '';

  # Upstream has no automated tests.  Start the game on a pseudo-terminal
  # and wait for its first screen, which needs the Lua library, both data
  # modules and the curses console.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ util-linux ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$TMPDIR/home TERM=xterm
    mkdir -p $HOME
    mkfifo keys
    script -qefc "stty rows 30 cols 100; $out/bin/drl" session.log < keys > /dev/null &
    session=$!
    exec 3> keys
    tries=0
    until grep -aqF 'continue...' session.log 2>/dev/null; do
      tries=$((tries + 1))
      if [ $tries -gt 60 ]; then
        echo 'drl did not reach its first screen' >&2
        cat $HOME/.local/state/drl/runtime.log >&2 || true
        exit 1
      fi
      sleep 1
    done
    kill $session
    exec 3>&-
    wait $session || true
    grep -qF 'BASE MODULE VERSION: ${finalAttrs.version}' $HOME/.local/state/drl/runtime.log

    runHook postInstallCheck
  '';

  meta = {
    description = "Console roguelike in the setting of a classic first-person shooter";
    longDescription = ''
      DRL, formerly DoomRL, is a fast turn-based roguelike by Kornel
      Kisielewicz.  This package builds release 0.10.11 with Free Pascal and
      the FPC Valkyrie library and installs the text console game only: tile
      graphics, fonts, music and sound are left out.  Saved games, scores,
      settings and logs are kept in $XDG_STATE_HOME/drl.  The game needs a
      terminal of at least 80 by 25 characters.
    '';
    homepage = "https://drl.chaosforge.org/";
    # DRL is GPL-2.0, FPC Valkyrie is MIT.
    license = with lib.licenses; [
      gpl2Only
      mit
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "drl";
  };
})
