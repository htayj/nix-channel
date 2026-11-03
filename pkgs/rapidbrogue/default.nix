{ lib, stdenv, fetchFromGitHub, fetchurl, makeWrapper, pkg-config, SDL2, SDL2_image
, ncurses, coreutils }:

let
  gpl3Text = fetchurl {
    url = "https://www.gnu.org/licenses/gpl-3.0.txt";
    hash = "sha256-OXLcl0T2SZ8Pmy2/dmlvKuetivmyPd5m1q+Gyd+zaYY=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rapidbrogue";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "flend";
    repo = "RapidBrogue";
    rev = "rapid_brogue-v${finalAttrs.version}";
    hash = "sha256-EOa0vp0RqEctP6IWumM84nUg8Ek5JVlszsC190nSGMk=";
  };

  nativeBuildInputs = [ makeWrapper pkg-config SDL2 ];
  buildInputs = [ SDL2 SDL2_image ncurses ];

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "RELEASE=YES"
    "TERMINAL=YES"
    "GRAPHICS=YES"
    "WEBBROGUE=NO"
    "MAC_APP=NO"
    "RAPIDBROGUE=YES"
    "DATADIR=${placeholder "out"}/share/rapidbrogue"
  ];

  # sdl2-config only names the SDL2 include directory of SDL2 itself.
  env.NIX_CFLAGS_COMPILE = "-I${lib.getDev SDL2_image}/include/SDL2";

  buildFlags = [ "bin/brogue" ];

  # This release has neither a check target nor a test suite.
  doCheck = false;

  # The game reads its keymap and writes saves, recordings, high scores and
  # screenshots relative to the working directory, so the launcher runs it
  # from an XDG state directory seeded with an editable keymap.
  installPhase = ''
    runHook preInstall

    data=$out/share/rapidbrogue
    doc=$out/share/doc/rapidbrogue

    install -Dm755 bin/brogue $out/libexec/rapidbrogue
    mkdir -p $data
    cp -r bin/assets $data/assets
    install -Dm644 -t $data bin/keymap.txt
    install -Dm644 -t $doc BUILD.md README.md CHANGELOG.md LICENSE.txt
    install -Dm644 bin/assets/LICENSE.txt $doc/assets/LICENSE.txt
    install -Dm644 ${gpl3Text} $doc/GPL-3.0.txt
    install -Dm644 -t $doc/source-notices \
      src/brogue/Rogue.h src/brogue/Dijkstra.c \
      src/platform/PlatformDefines.h src/platform/platformdependent.c

    mkdir -p $out/bin
    cat > $out/bin/rapidbrogue <<EOF
    #!${stdenv.shell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/rapidbrogue"
    ${coreutils}/bin/mkdir -p "\$state"
    if test ! -e "\$state/keymap.txt"; then
      ${coreutils}/bin/cp $data/keymap.txt "\$state/keymap.txt"
      ${coreutils}/bin/chmod u+w "\$state/keymap.txt"
    fi
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    cd "\$state"
    exec $out/libexec/rapidbrogue "\$@" --data-dir $data
    EOF
    chmod 555 $out/bin/rapidbrogue

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/rapidbrogue/assets/tiles.bin
    test -s $out/share/rapidbrogue/assets/tiles.png
    grep -q "$out/share/rapidbrogue" $out/libexec/rapidbrogue
    $out/libexec/rapidbrogue --help | grep -q -- --data-dir
    runHook postInstallCheck
  '';

  meta = {
    description = "Ten-level rapid variant of the Brogue roguelike";
    longDescription = ''
      RapidBrogue compresses Brogue Community Edition into ten levels, with
      the Amulet on level six, a faster difficulty curve and strengthened
      magic items.  It keeps the SDL interface with text, tile and hybrid
      graphics and adds the optional ncurses frontend (-t).  Saves,
      recordings, high scores and the editable keymap live in
      $XDG_STATE_HOME/rapidbrogue.
    '';
    homepage = "https://github.com/flend/RapidBrogue";
    # Engine AGPL-3.0+, legacy platform files GPL-3.0+, tile atlas CC BY-SA 4.0.
    license = with lib.licenses; [ agpl3Plus gpl3Plus cc-by-sa-40 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "rapidbrogue";
  };
})
