{ lib, stdenv, fetchFromGitHub, ncurses, coreutils }:

stdenv.mkDerivation {
  pname = "brogue-lite";
  version = "1.13-unstable-2024-01-05";

  # Maintained master after the Lite-v1.11.1-RC2 tag: the Brogue CE 1.13
  # merge with the later Lite probability fixes.
  src = fetchFromGitHub {
    owner = "HomebrewHomunculus";
    repo = "BrogueCE";
    rev = "8ee03a62f7787a796678553fd4f2d27a388f695f";
    hash = "sha256-EbAt+ZeFunmAhSncMgurgPQCokuVFz9fxfYTXNbalwQ=";
  };

  buildInputs = [ ncurses ];

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "RELEASE=YES"
    "GRAPHICS=NO"
    "TERMINAL=YES"
    "WEBBROGUE=NO"
    "DATADIR=${placeholder "out"}/share/brogue-lite"
  ];

  buildFlags = [ "bin/brogue" ];

  # The only upstream test is a regression runner whose recordings are not
  # part of the source checkout.
  doCheck = false;

  # The game reads its keymap and writes saves, recordings, high scores and
  # RNG logs relative to the working directory, so the launcher runs it from
  # an XDG state directory seeded with an editable keymap.  --data-dir comes
  # last so the packaged resources always win.
  installPhase = ''
    runHook preInstall

    data=$out/share/brogue-lite
    doc=$out/share/doc/brogue-lite

    install -Dm755 bin/brogue $out/libexec/brogue-lite
    install -Dm644 -t $data bin/keymap.txt
    install -Dm644 -t $doc README.md CHANGELOG.md CHANGELOG_LITE.md LICENSE.txt
    # Notice for the omitted CC BY-SA tile assets.
    install -Dm644 bin/assets/LICENSE.txt $doc/assets/LICENSE.txt

    mkdir -p $out/bin
    cat > $out/bin/brogue-lite <<EOF
    #!${stdenv.shell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/brogue-lite"
    ${coreutils}/bin/mkdir -p "\$state"
    if test ! -e "\$state/keymap.txt"; then
      ${coreutils}/bin/cp $data/keymap.txt "\$state/keymap.txt"
      ${coreutils}/bin/chmod u+w "\$state/keymap.txt"
    fi
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    cd "\$state"
    exec $out/libexec/brogue-lite "\$@" --data-dir $data
    EOF
    chmod 555 $out/bin/brogue-lite

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s $out/share/brogue-lite/keymap.txt
    grep -q "$out/share/brogue-lite" $out/libexec/brogue-lite
    $out/libexec/brogue-lite --help | grep -q -- --data-dir
    runHook postInstallCheck
  '';

  meta = {
    description = "Casual terminal variant of the Brogue roguelike";
    longDescription = ''
      Brogue Lite is a casual variant of Brogue Community Edition with fewer
      item and monster types and a shorter dungeon.  This package builds the
      ncurses terminal frontend only.  Saves, recordings, high scores, RNG
      logs and the editable keymap live in $XDG_STATE_HOME/brogue-lite.
    '';
    homepage = "https://github.com/HomebrewHomunculus/BrogueCE";
    # Engine AGPL-3.0+, legacy platform files GPL-3.0+; the omitted tile
    # assets are CC BY-SA 4.0 and only their notice is installed.
    license = with lib.licenses; [ agpl3Plus gpl3Plus cc-by-sa-40 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "brogue-lite";
  };
}
