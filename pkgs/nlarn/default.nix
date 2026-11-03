{ lib, stdenv, fetchFromGitHub, pkg-config, gettext, glib, ncurses, zlib }:

stdenv.mkDerivation (finalAttrs: {
  pname = "nlarn";
  version = "0.8.0";

  # Commit tagged by the annotated v0.8.0 release tag.  The PDCurses
  # submodule is only needed for the SDL build and is not fetched.
  src = fetchFromGitHub {
    owner = "nlarn";
    repo = "nlarn";
    rev = "1873599a5682e4645e2801f7de6bd11ce54c2dfd";
    hash = "sha256-mIyKqBVGwyCDjlAgCIN98RSd1iE5zs9nNP0PMYUsjUk=";
  };

  nativeBuildInputs = [ pkg-config gettext ];
  buildInputs = [ glib ncurses zlib ];

  postPatch = ''
    # The game falls back to this directory when no lib directory sits next
    # to the executable; point it at the store copy of the game data.
    substituteInPlace src/nlarn.c \
      --replace-fail '"/usr/share/nlarn"' "\"$out/share/nlarn\""
  '';

  dontConfigure = true;
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" "config=release" ];
  # Upstream has no test target.
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm755 nlarn $out/bin/nlarn
    install -Dm644 -t $out/share/nlarn \
      lib/fortune* lib/maze lib/nlarn.hlp* lib/nlarn.msg*
    cp -r lib/locale $out/share/nlarn/locale
    install -Dm644 -t $out/share/doc/nlarn \
      LICENSE README.md Changelog.md lib/maze_doc.txt
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    grep -q "$out/share/nlarn" $out/bin/nlarn
    test -s $out/share/nlarn/nlarn.msg
    test -s $out/share/nlarn/locale/de/LC_MESSAGES/nlarn.mo
    runHook postInstallCheck
  '';

  meta = {
    description = "Curses roguelike game inspired by Larn";
    longDescription = ''
      NLarn is a C and ncurses rewrite of the classic roguelike Larn.  Game
      data and translations are installed in the store; configuration, saves
      and high scores are kept in the user's configuration directory.
    '';
    homepage = "https://github.com/nlarn/nlarn";
    # cJSON is MIT; inc/external/enumFactory.h is CC-BY-SA 3.0.
    license = with lib.licenses; [ gpl3Plus mit cc-by-sa-30 ];
    mainProgram = "nlarn";
    platforms = [ "x86_64-linux" ];
  };
})
