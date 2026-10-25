{ lib, stdenv, fetchFromGitHub, SDL2 }:

stdenv.mkDerivation {
  pname = "vt05";
  # Upstream has no release tags.
  version = "0.1-unstable-934fe88";

  src = fetchFromGitHub {
    owner = "aap";
    repo = "vt05";
    rev = "934fe8898bd656749b323abbdab62939148cfe3e";
    hash = "sha256-hg6OZvqLbDuJXSM/vwkb4Wck7JpeMcwv4swphKDvvAo=";
  };

  # The Makefile hardcodes `cc`.
  postPatch = ''
    substituteInPlace Makefile --replace-fail 'cc ' '$(CC) '
  '';

  # sdl2-config supplies the SDL headers and libraries.
  nativeBuildInputs = [ SDL2 ];
  buildInputs = [ SDL2 ];

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin vt05 vt52 vt50 dp3300 gecon dm2500
    install -Dm644 -t $out/share/doc/vt05 LICENSE
    runHook postInstall
  '';

  meta = {
    description = "SDL emulators for several classic text terminals";
    longDescription = ''
      VT05 provides SDL2 graphical emulators for the DEC VT05, VT50, and
      VT52 terminals, the Datapoint 3300, the General Electric console
      terminal, and the Datamedia Elite 2500.  Each program opens a local SDL
      window and starts a command on a POSIX pseudo-terminal.
    '';
    homepage = "https://github.com/aap/vt05";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "vt05";
  };
}
