{ lib, stdenv, fetchFromGitHub, fetchgit }:

let
  # XPL-to-C translator used only to compile the PDP-10 XPL compiler port.
  xpl-bootstrap = stdenv.mkDerivation {
    pname = "xpl-bootstrap";
    version = "1.4";

    src = fetchgit {
      url = "https://git.code.sf.net/p/xpl-compiler/code";
      rev = "643907731538b4e2256f11c48e3166bf5bb2609c";
      hash = "sha256-CjAxTUXbI4I/HcXR/Sn1atne3uRPSXVWPxtmPohO7oI=";
    };

    makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

    installPhase = ''
      runHook preInstall
      install -Dm755 -t $out/bin xpl
      install -Dm644 -t $out/lib libxpl.a
      install -Dm644 -t $out/include xpl.h
      runHook postInstall
    '';

    meta.license = lib.licenses.bsd0;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pdp10-xpl-pdp-10";
  version = "0-unstable-0e57cbd";

  src = fetchFromGitHub {
    owner = "PDP-10";
    repo = "xpl-pdp-10";
    rev = "0e57cbd9e2e2997134332f6784dccc262a069d99";
    hash = "sha256-CJOQ1o76G0125r5Svcp9vzPmiX56aHiJcaOqBaSk34g=";
  };

  # The makefile records the maintainer's macOS path; use the bootstrap input.
  postPatch = ''
    substituteInPlace port/makefile \
      --replace-fail 'XPLDIR=/Users/linda/xpl' 'XPLDIR=${xpl-bootstrap}' \
      --replace-fail 'CFLAGS= -I $(XPLDIR) -Wno-parentheses-equality' 'CFLAGS= -I $(XPLDIR)/include' \
      --replace-fail 'XPL=$(XPLDIR)/xpl' 'XPL=$(XPLDIR)/bin/xpl' \
      --replace-fail 'LIBXPL=$(XPLDIR)/libxpl.a' 'LIBXPL=$(XPLDIR)/lib/libxpl.a'
  '';

  makeFlags = [ "-C" "port" "CC=${stdenv.cc.targetPrefix}cc" "xpl" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 port/xpl $out/libexec/pdp10-xpl/xpl
    install -Dm644 -t $out/share/pdp10-xpl port/xpl.lib port/hello.xpl
    install -Dm644 -t $out/share/doc/pdp10-xpl-pdp-10 COPYING README
    mkdir -p $out/bin
    cat > $out/bin/xpl <<EOF
    #!${stdenv.shell}
    exec $out/libexec/pdp10-xpl/xpl -l $out/share/pdp10-xpl/xpl.lib "\$@"
    EOF
    chmod 555 $out/bin/xpl
    runHook postInstall
  '';

  # Compile the bundled hello program to a PDP-10 relocatable file.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cp $out/share/pdp10-xpl/hello.xpl .
    chmod u+w hello.xpl
    $out/bin/xpl hello.xpl -KOBEA
    test -s hello.rel
    runHook postInstallCheck
  '';

  passthru = { inherit xpl-bootstrap; };

  meta = {
    description = "PDP-10 XPL compiler port";
    longDescription = ''
      Host cross compiler for the historical PDP-10 XPL dialect (XCOM 4,
      DECUS 20-0122), translated to C with the XPL-to-C bootstrap compiler.
      It produces PDP-10 relocatable output.
    '';
    homepage = "https://github.com/PDP-10/xpl-pdp-10";
    license = lib.licenses.bsd0; # Free Public License 1.0.0
    mainProgram = "xpl";
    platforms = [ "x86_64-linux" ];
  };
})
