{ lib, stdenv, fetchFromGitHub, runtimeShell }:

stdenv.mkDerivation {
  pname = "image-tape";
  version = "0-unstable-2022-01-26";

  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "image-tape";
    rev = "0402e216bbd0c3485a8c99bcdb853248763d1b5d";
    hash = "sha256-gYvGEMzjyt4vV80KeJy3ybru6HPGXg41H7CcpbZvAQw=";
  };

  # Retry short and interrupted writes, create the output file and report
  # output failures through the exit status.
  patches = [ ./safe-output.patch ];

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin image-tape
    install -Dm644 -t $out/share/doc/image-tape LICENSE
    runHook postInstall
  '';

  # Exercises argument, device and output errors without tape hardware.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${runtimeShell} ${./smoke.sh} $out/bin/image-tape
    runHook postInstallCheck
  '';

  meta = {
    description = "Read magnetic tape devices into tape image files";
    longDescription = ''
      Image-tape reads records and tape marks from a magnetic tape device and
      writes them as a tape image with length-framed records to standard
      output or to a named output file.
    '';
    homepage = "https://github.com/larsbrinkhoff/image-tape";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "image-tape";
  };
}
