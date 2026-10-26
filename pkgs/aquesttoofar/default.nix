{ lib, stdenv, fetchurl, unzip, makeWrapper, SDL }:

stdenv.mkDerivation {
  pname = "aquesttoofar";
  version = "1.3";

  # Fixed upstream release dated 2010-10-09.
  src = fetchurl {
    url = "https://www.randomstuff.org.uk/~geoffrey/roguelikes/AQuestTooFar1.3-091010.zip";
    hash = "sha256-N3uZoLWbhclmyFt/DcKH2wkpPbOaFXx68Yifrd3Hm5w=";
  };

  # Never retain the bundled Windows executable and SDL.dll.  With
  # --as-needed, libraries must follow the objects that reference them.
  postPatch = ''
    find . -name '*.exe' -delete -o -name '*.dll' -delete
    substituteInPlace makefile \
      --replace-fail '$(CC) $(LDFLAGS) $(OBJECTS) -o $(EXEC)' \
                     '$(CC) $(OBJECTS) -o $(EXEC) $(LDFLAGS)'
  '';

  nativeBuildInputs = [ unzip makeWrapper SDL ];
  buildInputs = [ SDL ];

  # The Build directory prerequisite is not shared by the object rules.
  enableParallelBuilding = false;
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}c++" ];

  # main.cpp loads its bitmaps relative to the working directory; the game
  # writes no saves or settings.
  installPhase = ''
    runHook preInstall
    install -Dm755 AQuestTooFar $out/libexec/aquesttoofar/AQuestTooFar
    install -Dm644 -t $out/share/aquesttoofar/Data Data/icon32.bmp Data/tiles_ascii.bmp
    install -Dm644 -t $out/share/doc/aquesttoofar readme.txt gpl-3.0.txt
    makeWrapper $out/libexec/aquesttoofar/AQuestTooFar $out/bin/aquesttoofar \
      --chdir $out/share/aquesttoofar
    runHook postInstall
  '';

  meta = {
    description = "Dungeon adventure starring an aging hero";
    longDescription = ''
      A Quest Too Far is a graphical ASCII roguelike in which a retired hero
      returns to the dungeon to rescue his grandchildren.  Every turn
      accumulates physical decline instead of experience.  This builds the
      original C++ game and its bundled CharLib with SDL 1.2 compatibility.
    '';
    homepage = "https://www.randomstuff.org.uk/~geoffrey/roguelikes/aquesttoofar.html";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "aquesttoofar";
  };
}
