{
  lib,
  stdenv,
  fetchurl,
  unzip,
  ncurses,
  runtimeShell,
}:

stdenv.mkDerivation {
  pname = "dhack";
  # 0.2c is the latest named release; the archive ends at SVN r47, and r45 is
  # the last revision that changed trunk sources.
  version = "0.2c";

  src = fetchurl {
    url = "https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/dreamhack/source-archive.zip";
    name = "dreamhack-source-r47.zip";
    hash = "sha256-QsRNkzQ7tLIErgizk4xnGM/D1d5I12mNFwXY2ZNLqcw=";
  };

  # Build only trunk: skip oldtrunk, the wiki, and the prebuilt Windows binary.
  sourceRoot = "dreamhack/trunk";

  nativeBuildInputs = [ unzip ];
  buildInputs = [ ncurses ];

  dontConfigure = true;

  # Pass the status line through a literal format for -Werror=format-security.
  postPatch = ''
    substituteInPlace CEngine.cpp \
      --replace-fail 'mvprintw(1,40,m_BottomText[i].c_str());' \
                     'mvprintw(1,40,"%s",m_BottomText[i].c_str());'
  '';

  # The upstream makefile names its output "main"; build the same four
  # translation units directly with an explicit language mode.
  buildPhase = ''
    runHook preBuild
    $CXX -std=c++14 $NIX_CFLAGS_COMPILE -O2 \
      main.cpp global.cpp CGame.cpp CEngine.cpp -o dhack -lncurses
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 dhack $out/libexec/dhack/dhack
    install -Dm644 -t $out/share/doc/dhack COPYING
    mkdir -p $out/bin
    cat > $out/bin/dhack <<EOF
    #!${runtimeShell}
    set -eu
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    exec $out/libexec/dhack/dhack "\$@"
    EOF
    chmod 555 $out/bin/dhack
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/dhack/dhack
    grep -qF "GNU GENERAL PUBLIC LICENSE" $out/share/doc/dhack/COPYING
    runHook postInstallCheck
  '';

  meta = {
    description = "Historical DreamHack terminal symbolic roguelike";
    longDescription = ''
      Dhack is the standalone DreamHack symbolic roguelike, built from the
      four C++ sources of the archived Google Code trunk at its final code
      revision and linked with ncurses.  The game keeps no saves or other
      runtime state.
    '';
    homepage = "https://code.google.com/archive/p/dreamhack";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "dhack";
  };
}
