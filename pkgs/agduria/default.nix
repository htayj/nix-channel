{ lib, stdenv, fetchFromGitHub, makeWrapper, ncurses }:

stdenv.mkDerivation {
  pname = "agduria";
  # Upstream has no release tags; the game reports version 0.0.1.
  version = "0.0.1-unstable-92c20b1";

  src = fetchFromGitHub {
    owner = "paulpekkarinen";
    repo = "Agduria";
    rev = "92c20b10724dcd7ba6ca3ccbf794600d8df01b7c";
    hash = "sha256-F+A+bEgSKIDgf4j3BboS/pFBigH7wjwwJHZCNlOLBfk=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ ncurses ];

  # Libraries must follow objects with --as-needed linkers.
  postPatch = ''
    substituteInPlace makefile \
      --replace-fail '$(CXX) $(LIBS) -o $@ $^' '$(CXX) -o $@ $^ $(LIBS)'
  '';

  # Upstream CXXFLAGS already select C++20; only optimisation is added.
  makeFlags = [ "CXX=${stdenv.cc.targetPrefix}c++" ];
  env.NIX_CFLAGS_COMPILE = "-O2";

  installPhase = ''
    runHook preInstall
    install -Dm755 agduria $out/libexec/agduria/agduria
    makeWrapper $out/libexec/agduria/agduria $out/bin/agduria \
      --prefix TERMINFO_DIRS : ${ncurses}/share/terminfo
    install -Dm644 -t $out/share/doc/agduria LICENSE.md README.md
    runHook postInstall
  '';

  meta = {
    description = "Terminal roguelike with procedurally generated dungeons";
    longDescription = ''
      Agduria is a standalone terminal roguelike using ncurses for colored
      ASCII graphics.  This early version provides dungeon exploration and
      an interactive creature-system demonstration.  It requires an 80 by 24
      color terminal.  The game has no save or load implementation and does
      not create user files.
    '';
    homepage = "https://www.kriceland.fi/agduria/index.html";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "agduria";
  };
}
