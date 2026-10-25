{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "tapeutils";
  # Upstream's Makefile identifies this fixed revision as version 0.6.
  version = "0.6-unstable-84a3a78";

  src = fetchFromGitHub {
    owner = "brouhaha";
    repo = "tapeutils";
    rev = "84a3a78d2c028d7a4e2e68b89be0411cebd94563";
    hash = "sha256-PKI2oY2wCpfnk8+iqgI5/9zY8JU4aONZBUZeyyVrUe0=";
  };

  # The BSD make shell assignment is the only construct GNU make rejects.
  postPatch = ''
    substituteInPlace Makefile --replace-fail 'UNAME != uname' 'UNAME := $(shell uname)'
  '';

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  # read20.c uses K&R declarations such as `extern char *re_comp();`, which
  # C23 treats as zero-argument prototypes.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin tapecopy tapedump taperead tapewrite t10backup read20 tapex
    install -Dm644 -t $out/share/doc/tapeutils COPYING
    runHook postInstall
  '';

  meta = {
    description = "Read, write, and inspect magnetic-tape image files";
    longDescription = ''
      Tapeutils provides command-line programs for reading, writing, copying,
      and inspecting magnetic tapes and Wilson-format tape image files.  A
      pathname that does not name a device is handled as a local tape image.
    '';
    homepage = "https://github.com/brouhaha/tapeutils";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "tapedump";
  };
}
