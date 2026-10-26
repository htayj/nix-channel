{
  lib,
  stdenv,
  fetchFromGitHub,
  ncurses,
  coreutils,
  runtimeShell,
}:

stdenv.mkDerivation {
  pname = "freelarn";
  version = "0-unstable-8cd18cb";

  # No upstream release tags exist; this is the canonical 2022-07-25 commit.
  src = fetchFromGitHub {
    owner = "atsb";
    repo = "freelarn";
    rev = "8cd18cbaef70b9763a9f76cdfa11b78524ebcf5e";
    hash = "sha256-pTy80HAI6x4cGj9JY9HuxtLUj3NVyxhC3oVIevPkzsY=";
  };

  buildInputs = [ ncurses ];

  # Upstream treats every warning as an error; keep its portability flags but
  # let current compilers warn without failing the build.
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail "CC = g++" "CC = ${stdenv.cc.targetPrefix}c++" \
      --replace-fail " -Werror" ""
  '';

  dontConfigure = true;
  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/freelarn $out/libexec/freelarn/freelarn
    install -Dm644 -t $out/share/doc/freelarn LICENSE README.md
    install -Dm644 -t $out/share/doc/freelarn/docs docs/LICENSE docs/HISTORY docs/CHANGELOG
    mkdir -p $out/bin
    cat > $out/bin/freelarn <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/freelarn"
    ${coreutils}/bin/mkdir -p -- "\$state"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    cd -- "\$state"
    exec $out/libexec/freelarn/freelarn "\$@"
    EOF
    chmod 555 $out/bin/freelarn
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/freelarn/freelarn
    grep -qF "Apache License" $out/share/doc/freelarn/LICENSE
    runHook postInstallCheck
  '';

  meta = {
    description = "C++11 descendant of the Larn dungeon game";
    longDescription = ''
      FreeLarn is a C++11 descendant of the classic Larn dungeon game.  The
      launcher keeps saves, scores, and message logs in
      $XDG_STATE_HOME/freelarn, falling back to ~/.local/state/freelarn.
    '';
    homepage = "https://github.com/atsb/freelarn";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "freelarn";
  };
}
