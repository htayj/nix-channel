{ lib, stdenv, fetchurl, SDL }:

stdenv.mkDerivation (finalAttrs: {
  pname = "cracks-and-crevices";
  version = "0.5";

  # Original release attachment 32; the author's host is gone, so fetch the
  # archived copy.  121192 bytes, MD5 dd6e27a5bfea81549c94d52c12b9682e.
  src = fetchurl {
    url = "https://web.archive.org/web/20150804175538if_/https://redmine.bloodycactus.com/attachments/download/32/cracks_and_crevices-${finalAttrs.version}.tar.bz2";
    hash = "sha256-oAz2qwoYlnP+FS+TJbFMGmtqUxqFENHMMhxEzN65+2Y=";
  };

  # Maintenance patches shared with the Guix channel: library notices and
  # provenance, private per-user XDG state, and current-compiler fixes.
  patches = [
    ./cracks-and-crevices-notices.patch
    ./cracks-and-crevices-native-state.patch
    ./cracks-and-crevices-build.patch
    # Nix channel: check fortified input results and drop a dead variable
    # reported by GCC 16, keeping -Werror and _FORTIFY_SOURCE.
    ./cracks-and-crevices-gcc16-io.patch
    # Nix channel: saved lists name their element destructor by identifier.
    # The original stored its address, which is wrong in the next process of a
    # position-independent build and crashed every restored game.
    ./cracks-and-crevices-save-destructors.patch
  ];
  patchFlags = [ "-p1" "--fuzz=0" ];

  dontConfigure = true;

  buildInputs = [ SDL ];

  # The sources include <SDL/SDL.h>.
  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "CPPFLAGS=-I${lib.getDev SDL}/include"
    "LDFLAGS=-L${lib.getLib SDL}/lib"
  ];

  # Upstream's install target is a setgid /usr/games plus /var/games setup.
  # Fonts, maps and game data are compiled into cnc; scores, saves and
  # configuration live in the player's private XDG state directory.
  installPhase = ''
    runHook preInstall
    install -Dm755 cnc $out/libexec/cracks-and-crevices/cnc
    mkdir -p $out/bin
    ln -s ../libexec/cracks-and-crevices/cnc $out/bin/cracks-and-crevices
    doc=$out/share/doc/cracks-and-crevices
    mkdir -p $doc
    cp -r docs/. $doc/
    install -m644 config-example.ini PROVENANCE.txt $doc/
    install -Dm644 -t $doc/licenses COPYING.libfov random_mt.c memwatch.c memwatch.h
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/cracks-and-crevices/cnc
    test "$(readlink $out/bin/cracks-and-crevices)" = ../libexec/cracks-and-crevices/cnc
    for f in COPYING readme.txt PROVENANCE.txt licenses/COPYING.libfov \
             licenses/random_mt.c licenses/memwatch.c licenses/memwatch.h; do
      test -s $out/share/doc/cracks-and-crevices/$f
    done
    grep -q 'XDG_STATE_HOME' $out/libexec/cracks-and-crevices/cnc
    ! grep -q '/var/games' $out/libexec/cracks-and-crevices/cnc
    test -z "$(find $out -perm -2000 -o -perm -4000)"
    runHook postInstallCheck
  '';

  meta = {
    description = "Real-time dungeon-crawling roguelike";
    longDescription = ''
      Cracks and Crevices is a real-time dungeon-crawling roguelike with
      character advancement, quests, shops and configurable SDL bitmap fonts.
      This package builds the original 0.5 release.  Configuration, saved
      games, character dumps and scores live in a private per-user XDG state
      directory.
    '';
    homepage = "https://web.archive.org/web/20160417095515id_/https://redmine.bloodycactus.com/projects/sdlrl/files";
    # Game GPL-2.0-only (docs/readme.txt), libfov MIT, MT19937 BSD-3,
    # MEMWATCH GPL-2.0-or-later.
    license = with lib.licenses; [ gpl2Only mit bsd3 gpl2Plus ];
    mainProgram = "cracks-and-crevices";
    platforms = [ "x86_64-linux" ];
  };
})
