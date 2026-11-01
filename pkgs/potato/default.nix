{ lib, stdenvNoCC, fetchFromGitHub, tcl, tk, tclPackages }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "potato";
  version = "2.0.0b19";

  # 2.0.0b19 is an annotated tag; pin the dereferenced release commit.
  src = fetchFromGitHub {
    owner = "potatomushclient";
    repo = "potato";
    rev = "8f187da3ceddcc0e355f0f14d2060ed381d73bc3";
    hash = "sha256-3KwaS/rNx/DeV8TB3Z+LCAWiqQv9JvyHZUktlXNmi50=";
  };

  dontConfigure = true;
  dontBuild = true;
  # Preserve the upstream sources and desktop entry byte for byte.
  dontPatchShebangs = true;
  dontStrip = true;

  # The Starkit tree carries Windows DLLs, macOS dylibs and a Linux linflash
  # extension that compiles itself in the user's profile; Potato falls back to
  # a no-op taskbar flash without them.  The package manager handles updates,
  # so the cleartext HTTP update check is never scheduled, even when an old
  # profile re-enables it.  Upstream imports Tcl TLS with certificate
  # validation disabled and Tcl TLS has no hostname validation, so TLS is
  # reported unavailable instead.  The sources are ISO-8859-1; sed edits the
  # ASCII-only lines byte for byte.
  postPatch = ''
    rm -r potato.vfs/lib/app-potato/{windows,macosx,linux}

    sed -i 's|set misc(checkForUpdates) 1|set misc(checkForUpdates) 0|' \
      potato.vfs/lib/potato-config.tcl
    grep -q 'set misc(checkForUpdates) 0' potato.vfs/lib/potato-config.tcl

    sed -i 's|if { $misc(checkForUpdates) } {|if {0} { ;# Nix package disables scheduled cleartext update checks|' \
      potato.vfs/lib/potato.tcl
    grep -q 'Nix package disables scheduled' potato.vfs/lib/potato.tcl

    sed -i 's|if { \[catch {package require tls 1.6.7-} reqtls errdict\] } {|if {1} { set reqtls {TLS disabled by the Nix package: Tcl TLS lacks hostname validation}; set errdict {}|' \
      potato.vfs/lib/potato.tcl
    grep -q 'TLS disabled by the Nix package' potato.vfs/lib/potato.tcl
    ! grep -q 'package require tls' potato.vfs/lib/potato.tcl
  '';

  # Check that every retained Tcl source and module is syntactically complete,
  # without running it.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cat > syntax-check.tcl <<'EOF'
    set failed 0
    foreach file $argv {
      set fd [open $file r]
      fconfigure $fd -encoding utf-8
      set source [read $fd]
      close $fd
      if {![info complete $source]} {
        puts stderr "incomplete Tcl source: $file"
        set failed 1
      }
    }
    exit $failed
    EOF
    find . \( -name '*.tcl' -o -name '*.tm' \) ! -name syntax-check.tcl -print0 \
      | xargs -0 ${tcl}/bin/tclsh syntax-check.tcl
    rm syntax-check.tcl
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec $out/bin
    cp -r potato.vfs $out/libexec/potato
    install -Dm644 potato.vfs/tools/linux/potato.desktop \
      $out/share/applications/potato.desktop
    install -Dm644 potato.vfs/tools/linux/potato.png \
      $out/share/icons/hicolor/55x55/apps/potato.png

    cat > $out/bin/potato <<EOF
    #!${stdenvNoCC.shell}
    if test "\''${1-}" = "--version"; then
        printf '%s\n' 'Potato MU* Client ${finalAttrs.version}'
        exit 0
    fi
    exec ${tk}/bin/wish $out/libexec/potato/main.tcl "\$@"
    EOF
    chmod 555 $out/bin/potato

    doc=$out/share/doc/potato
    install -Dm644 -t $doc README.md potato.vfs/{INSTALL,MANIFEST,LICENSE}
    # base64-2.4.2.tm is vendored Tcllib code that refers to license.terms.
    install -Dm644 ${tclPackages.tcllib}/lib/tcllib${tclPackages.tcllib.version}/tcllibc/license.terms \
      $doc/tcllib-license.terms
    cat > $doc/THIRD-PARTY-NOTICES <<'EOF'
    Potato bundled-component audit
    ==============================

    The application is distributed under the MIT/Expat license; see LICENSE.

    base64-2.4.2.tm: Tcllib base64 implementation.  Its source directs
    readers to license.terms; the Tcl/Tk terms from Nixpkgs tcllib are
    installed verbatim as tcllib-license.terms.

    crossplatform/listboxdnd/listboxdnd.tcl (ListboxDnD) and
    treeviewUtils/treeviewUtils.tcl (credits Keith Vetter's Tcl Wiki code):
    the pinned upstream tree contains no separate license files, so the
    original sources are retained unchanged under libexec/potato.

    Foreign Windows and macOS binary extensions and the self-compiling Linux
    linflash source are excluded.  TLS is disabled because the available Tcl
    TLS API lacks hostname validation.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$($out/bin/potato --version)" = 'Potato MU* Client ${finalAttrs.version}'
    test -f $out/libexec/potato/main.tcl
    test ! -e $out/libexec/potato/lib/app-potato/windows
    test ! -e $out/libexec/potato/lib/app-potato/macosx
    test ! -e $out/libexec/potato/lib/app-potato/linux
    test -s $out/share/doc/potato/tcllib-license.terms
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical Tcl/Tk MUSH client";
    longDescription = ''
      Potato is a graphical MUSH client written in Tcl/Tk.  It supports
      Telnet, scripting, triggers, aliases, events, logging and multiple
      worlds.  This package runs the pinned Tcl source tree with Nixpkgs Tcl
      and Tk.  TLS is disabled: the available Tcl TLS API cannot validate a
      server host name, and upstream otherwise accepts invalid certificates.
      The background update check is disabled.  Profiles, worlds, logs and
      plugins stay under the user's home directory.
    '';
    homepage = "https://github.com/potatomushclient/potato";
    license = with lib.licenses; [ mit tcltk ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "potato";
  };
})
