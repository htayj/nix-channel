{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation (finalAttrs: {
  pname = "ks10-udis";
  # Upstream has no release tags.
  version = "0-unstable-c41bced";

  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "ks10-udis";
    rev = "c41bcedde3ace1e68b2947ec220412e0f4a3d2ab";
    hash = "sha256-AHZcRhEITm7jDv6I4a7zbCW6xEL2Ndmwjuu6VrErY+Q=";
  };

  # The Makefile hardcodes `gcc` for linking.
  postPatch = ''
    substituteInPlace Makefile --replace-fail 'gcc $(OBJS)' '$(CC) $(OBJS)'
  '';

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  # The bundled ITS microcode image is a deterministic offline smoke test.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./udis < ram.262 > udis-smoke.out
    test -s udis-smoke.out
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin udis
    install -Dm644 -t $out/share/ks10-udis ram.262
    install -Dm644 -t $out/share/doc/ks10-udis README AUTHOR COPYING
    runHook postInstall
  '';

  meta = {
    description = "KS10 microcode disassembler";
    longDescription = ''
      KS10 UDIS disassembles KS10 microcode.  The package installs the udis
      command and the upstream ram.262 ITS microcode image under
      share/ks10-udis for offline inspection.
    '';
    homepage = "https://github.com/larsbrinkhoff/ks10-udis";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.unix;
    mainProgram = "udis";
  };
})
