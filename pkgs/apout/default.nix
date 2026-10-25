{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation (finalAttrs: {
  pname = "apout";
  # Upstream calls this tree 2.4.0 but has no matching release tag.
  version = "0-unstable-bd9af21";

  src = fetchFromGitHub {
    owner = "DoctorWkt";
    repo = "Apout";
    rev = "bd9af21bd8bb2fa956dcda5db0b0aeec2cffc8f7";
    hash = "sha256-UUYDcKu2ZIy+OUXpcnJmrkgra828DaaVIg9lvqTOT5Y=";
  };

  # Correct the misspelled EMUv1 default option (the source tests EMUV1) and
  # require users to set APOUT_ROOT instead of assuming the host root.
  postPatch = ''
    substituteInPlace Makefile --replace-fail \
      'APOUT_OPTIONS?= -DEMU211 -DEMUv1 -DNATIVES' \
      'APOUT_OPTIONS?= -DEMU211 -DEMUV1 -DNATIVES -DAPOUT_DONT_ASSUME_ROOT'
  '';

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  buildFlags = [ "apout" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin apout
    install -Dm644 -t $out/share/man/man1 apout.1
    install -Dm644 -t $out/share/doc/apout README CHANGES LIMITATIONS TODO LICENSE COPYRIGHT
    runHook postInstall
  '';

  meta = {
    description = "Run PDP-11 Unix a.out binaries on a host system";
    longDescription = ''
      Apout emulates PDP-11 user-mode instructions and translates Unix system
      calls for V1, V2, V5, V6, V7, 2.9BSD and 2.11BSD a.out programs.  Set
      APOUT_ROOT to a user-owned guest root before use; apout rejects an unset
      value.  APOUT_ROOT is a pathname prefix, not a security sandbox.
    '';
    homepage = "https://github.com/DoctorWkt/Apout";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
    mainProgram = "apout";
  };
})
