{
  lib,
  stdenv,
  coreutils,
  fetchurl,
  gzip,
  ncurses,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "martins-dungeon-bash";
  version = "1.7";

  src = fetchurl {
    url = "https://www.chiark.greenend.org.uk/~mpread/dungeonbash/archive-${finalAttrs.version}/dungeonbash-${finalAttrs.version}.tar.gz";
    hash = "sha256-eQveBP+Gm6KBetHwfQYtdffxWvSiyZZp3WCkuY/fE4A=";
  };

  buildInputs = [ ncurses ];

  # Keep upstream warnings but let GCC 14 report historical
  # maybe-uninitialized diagnostics without failing.  Save and restore shell
  # out to gzip; use the store path so they do not depend on the caller's
  # PATH, and restore from the compressed file the save step produced.
  postPatch = ''
    substituteInPlace Makefile --replace-fail ' -Werror' ""
    substituteInPlace main.c \
      --replace-fail '"gzip dunbash.sav"' '"${gzip}/bin/gzip dunbash.sav"' \
      --replace-fail '"gunzip dunbash.sav"' '"${gzip}/bin/gunzip dunbash.sav.gz"'
  '';

  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 dungeonbash $out/libexec/martins-dungeon-bash/dungeonbash
    install -Dm644 notes.txt $out/share/doc/martins-dungeon-bash/notes.txt
    mkdir -p $out/bin
    cat > $out/bin/dungeonbash <<EOF
    #!${runtimeShell}
    set -eu
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    case "\''${XDG_STATE_HOME:-}" in
      /*) state="\$XDG_STATE_HOME" ;;
      *) state="\''${HOME:?HOME must be set when XDG_STATE_HOME is not absolute}/.local/state" ;;
    esac
    state="\$state/martins-dungeon-bash"
    ${coreutils}/bin/mkdir -p "\$state"
    cd "\$state"
    exec $out/libexec/martins-dungeon-bash/dungeonbash "\$@"
    EOF
    chmod 555 $out/bin/dungeonbash
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/martins-dungeon-bash/dungeonbash
    grep -q '${gzip}/bin/gunzip dunbash.sav.gz' $out/libexec/martins-dungeon-bash/dungeonbash
    runHook postInstallCheck
  '';

  meta = {
    description = "Simple terminal roguelike game";
    longDescription = ''
      Martin's Dungeon Bash is a small C roguelike built against ncurses and
      panel.  The launcher keeps saves, character dumps and the death log in
      $XDG_STATE_HOME/martins-dungeon-bash, defaulting to
      ~/.local/state/martins-dungeon-bash.  Saving exits the game; the next
      launch restores and consumes the save.
    '';
    homepage = "https://www.chiark.greenend.org.uk/~mpread/dungeonbash/";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.linux;
    mainProgram = "dungeonbash";
  };
})
