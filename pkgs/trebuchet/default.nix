{ lib
, stdenvNoCC
, fetchFromGitHub
, makeWrapper
, tcl
, tk
, tclPackages
, cacert
}:

let
  # Tcl's package search path is a Tcl list (space separated).  tcllib
  # mirrors the Guix inputs; tcltls provides the optional TLS support.
  tclLibPath = lib.concatStringsSep " " [
    "${tclPackages.tcllib}/lib/tcllib${tclPackages.tcllib.version}"
    "${tclPackages.tcltls}/lib/tcltls${tclPackages.tcltls.version}"
  ];
  caBundle = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "trebuchet";
  # Upstream has no release newer than v1081; master carries revision 1082
  # in Trebuchet.tcl.
  version = "1082";

  src = fetchFromGitHub {
    owner = "fuzzball-muck";
    repo = "trebuchet";
    rev = "1418ab604d870c154887adf2b0b6c8ec91457abe";
    hash = "sha256-xorQh2fkYdom+eaLodDWQRVpN6/aCftfte3BesktDY0=";
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ tcl ];

  # Network hardening mirrored from the Guix package.
  postPatch = ''
    # Keep the local control socket on loopback.
    substituteInPlace lib/remote.tcl \
      --replace-fail 'socket -server remote:connect $remote_port' \
                     'socket -server remote:connect -myaddr 127.0.0.1 $remote_port' \
      --replace-fail 'socket -async localhost $remote_port' \
                     'socket -async 127.0.0.1 $remote_port'

    # Trust the package-owned CA bundle instead of the stale 2019 bundle,
    # and drop the switch that restricts OpenSSL to TLS 1.0.
    substituteInPlace Trebuchet.tcl \
      --replace-fail 'set cafile [file join $treb_cacerts_dir "ca-bundle.crt"]' \
                     'set cafile "${caBundle}"' \
      --replace-fail '-cafile $cafile -cadir $treb_cacerts_dir' '-cafile $cafile' \
      --replace-fail '-tls1 1' '-tls1 0'

    # STARTTLS: same trust store and TLS version policy; certificate
    # verification fails closed; a failed handshake never continues or
    # reconnects in plaintext; no interactive trust override.
    substituteInPlace lib/secsupp.tcl \
      --replace-fail '-cadir $treb_cacerts_dir' '-cafile "${caBundle}"' \
      --replace-fail '-tls1 1' '-tls1 0' \
      --replace-fail 'puts stderr $err' 'puts stderr $err
                return 0' \
      --replace-fail 'if {[info commands ::tls::unimport] != ""} {' 'if {0} {' \
      --replace-fail 'tls::unimport $sok' '# TLS remains imported after a failed handshake' \
      --replace-fail 'catch {/socket:connect $world 1}' '# TLS failure: do not reconnect in plaintext' \
      --replace-fail 'Falling back to unencrypted link.' 'Closing connection.' \
      --replace-fail 'Reconnecting with unencrypted link.' 'Closing connection.' \
      --replace-fail 'proc tls_error_query {world errtxt cert} {' 'proc tls_error_query {world errtxt cert} {
    return "no"
    # Original interactive policy follows.'
  '';

  dontConfigure = true;
  dontBuild = true;
  dontPatchShebangs = true;
  dontStrip = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    # Offline Tcl parser check of every application and library script.
    cat > ../trebuchet-syntax-check.tcl <<'EOF'
    set files [concat [glob -nocomplain -- *.tcl] [glob -nocomplain -- lib/*.tcl]]
    if {[llength $files] < 2} { puts stderr "no Tcl sources found"; exit 1 }
    set failed 0
    foreach file $files {
      set fd [open $file r]
      set contents [read $fd]
      close $fd
      if {![info complete $contents]} {
        puts stderr "incomplete Tcl source: $file"
        set failed 1
      }
    }
    exit $failed
    EOF
    tclsh ../trebuchet-syntax-check.tcl

    # Confirm the hardened code paths and absence of plaintext fallback.
    grep -qF -- '-myaddr 127.0.0.1' lib/remote.tcl
    ! grep -qF 'socket -async localhost' lib/remote.tcl
    ! grep -rqF -- '-tls1 1' Trebuchet.tcl lib
    ! grep -rqF -- '-cadir' Trebuchet.tcl lib
    ! grep -qF 'tls::unimport $sok' lib/secsupp.tcl
    ! grep -qF 'socket:connect $world 1' lib/secsupp.tcl
    ! grep -qF 'unencrypted link' lib/secsupp.tcl
    test "$(grep -cF '${caBundle}' Trebuchet.tcl lib/secsupp.tcl | awk -F: '{s+=$2} END {print s}')" = 2

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/trebuchet $out/share/doc/trebuchet
    cp -r . $out/libexec/trebuchet/
    cp LICENSE README.md changes.txt $out/share/doc/trebuchet/

    makeWrapper ${tk}/bin/wish $out/bin/treb \
      --add-flags $out/libexec/trebuchet/Trebuchet.tcl \
      --prefix TCLLIBPATH " " "${tclLibPath}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x $out/bin/treb
    test -f $out/libexec/trebuchet/Trebuchet.tcl
    test -s ${caBundle}
    grep -qF '${tk}/bin/wish' $out/bin/treb
    grep -qF "$out/libexec/trebuchet/Trebuchet.tcl" $out/bin/treb
    for dir in ${tclLibPath}; do
      grep -qF "$dir" $out/bin/treb
    done

    # Headless library probe with the launcher's TCLLIBPATH.
    echo 'package require opt; package require tls; puts TREB_LIBS_OK' > probe.tcl
    TCLLIBPATH="${tclLibPath}" HOME=$TMPDIR ${tcl}/bin/tclsh probe.tcl | grep -qx TREB_LIBS_OK

    runHook postInstallCheck
  '';

  meta = {
    description = "Tcl/Tk graphical MUD, MUCK and MUSH client";
    homepage = "https://github.com/fuzzball-muck/trebuchet";
    license = with lib.licenses; [ gpl2Plus lgpl2Plus publicDomain ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "treb";
  };
})
