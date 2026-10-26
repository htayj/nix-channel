{
  lib,
  stdenv,
  fetchurl,
  ncurses,
  coreutils,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "avanor";
  version = "0.5.8";

  src = fetchurl {
    url = "https://downloads.sourceforge.net/project/avanor/avanor/${finalAttrs.version}/avanor-${finalAttrs.version}-src.tar.bz2";
    hash = "sha256-j1W+g9mFRwuaUiAmP8h9CgpuK2DbvJd8HEk0cyE3nvM=";
  };

  buildInputs = [ ncurses ];

  postPatch = ''
    substituteInPlace creature/Uniquem.cpp \
      --replace-fail "return NULL;" "return 0;"
    substituteInPlace game/cave.cpp \
      --replace-fail "r.Setup(&XRect(x, y, x + l, y + h));" \
        "XRect bounds(x, y, x + l, y + h); r.Setup(&bounds);"
    substituteInPlace item/item_misc.cpp \
      --replace-fail "sprintf(buf, name);" 'sprintf(buf, "%s", name);'
    # Keep the writable high-score table with the user's other state.
    substituteInPlace helpers/hiscore.h \
      --replace-fail 'vMakePath(DATA_DIR, "avanor.hsc")' 'vMakePath(HOME_DIR, "avanor.hsc")'
  '';

  dontConfigure = true;

  makeFlags = [
    "VERSION=${finalAttrs.version}"
    "CC=${stdenv.cc.targetPrefix}c++"
    "LD=${stdenv.cc.targetPrefix}c++"
    "DATA_DIR=${placeholder "out"}/share/avanor/"
    "LIBS=-lncurses"
    "OPTFLAGS=-O2"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 avanor $out/libexec/avanor/avanor
    mkdir -p $out/share/avanor $out/share/doc/avanor $out/bin
    cp -r manual $out/share/avanor/manual
    install -m644 COPYING gpl.txt README.txt $out/share/doc/avanor/
    cat > $out/bin/avanor <<EOF
    #!${runtimeShell}
    set -eu
    state_root="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}"
    state="\$state_root/.avanor"
    ${coreutils}/bin/mkdir -p -- "\$state"
    if test ! -e "\$state/avanor.hsc"; then
      : > "\$state/avanor.hsc"
    fi
    export HOME="\$state_root"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    cd -- "\$state"
    exec $out/libexec/avanor/avanor "\$@"
    EOF
    chmod 555 $out/bin/avanor
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/avanor/avanor
    test -f $out/share/avanor/manual/credits.html
    grep -qF "GNU GENERAL PUBLIC LICENSE" $out/share/doc/avanor/COPYING
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal fantasy roguelike";
    longDescription = ''
      Avanor is a curses-based fantasy roguelike.  The launcher keeps saves,
      high scores, recipes, and diagnostics in $XDG_STATE_HOME/.avanor,
      falling back to ~/.local/state/.avanor, and reads its manual from the
      package output.
    '';
    homepage = "https://sourceforge.net/projects/avanor/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "avanor";
  };
})
