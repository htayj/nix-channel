{ lib, stdenv, fetchFromGitHub, cmake, perl, pkg-config, gnutls, zlib
, runtimeShell }:

stdenv.mkDerivation (finalAttrs: {
  pname = "kbtin";
  # No release tag since 2.3; the tracked VERSION file names this commit.
  version = "2.3-unstable-2026-08-01";

  src = fetchFromGitHub {
    owner = "kilobyte";
    repo = "kbtin";
    rev = "9151634296e0591d918a4fd39e743fb9bef68f16";
    hash = "sha256-pODqKvBamaETmHsLOT1M6j3sDYVs2VsUCPj4Wvrones=";
  };

  # #system and #run exec a hard-coded /bin/sh.  The generator and test
  # scripts run during the build.
  postPatch = ''
    substituteInPlace run.cc --replace-fail '"/bin/sh"' '"${runtimeShell}"'
    patchShebangs get_version make_commands make_protos help2ansi a2html \
      fixmanual tests/runtest.sh
  '';

  nativeBuildInputs = [ cmake perl pkg-config ];
  buildInputs = [ gnutls zlib ];

  cmakeFlags = [
    "-DMCCP=ON"
    "-DSSL=ON"
    # Keep a host hyperscan out of the result.
    "-DSIMD=OFF"
  ];

  doCheck = true;

  postInstall = ''
    install -Dm644 -t $out/share/doc/kbtin \
      ../COPYING ../AUTHORS ../BUGS ../ChangeLog ../FAQ ../KEYPAD ../OLDNEWS \
      ../README.md
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/KBtin --version | grep -F 2.3-69-g9151634
    test -s $out/share/kbtin/KBtin_help.gz
    grep -aF '${runtimeShell}' $out/bin/KBtin >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "TinTin-compatible terminal MUD client";
    homepage = "https://github.com/kilobyte/kbtin";
    license = lib.licenses.gpl2Only;
    mainProgram = "kbtin";
    platforms = [ "x86_64-linux" ];
  };
})
