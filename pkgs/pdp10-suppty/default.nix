{ lib, stdenv, fetchFromGitHub, autoconf, automake, perl, pkg-config, halibut
, gtk2, libx11, krb5 }:

stdenv.mkDerivation {
  pname = "pdp10-suppty";
  # Upstream has no releases; based on PuTTY 0.66.
  version = "0-unstable-2da0135";

  src = fetchFromGitHub {
    owner = "PDP-10";
    repo = "SUPPTY";
    rev = "2da0135f2f3069db4b692155887d4076e67d6fac";
    hash = "sha256-E/M8jjz6N49s642Uy2IiPVq/3j0ESXPfM0WuN/eJTzk=";
  };

  nativeBuildInputs = [ autoconf automake perl pkg-config halibut ];
  buildInputs = [ gtk2 libx11 ];

  postPatch = ''
    # The SUPDUP backend is registered in be_all but missing from Recipe.
    substituteInPlace Recipe \
      --replace-fail "NONSSH   = telnet raw rlogin ldisc pinger" \
                     "NONSSH   = telnet raw rlogin ldisc pinger supdup"
    # ldisc_send has no local term; CLI ldiscs have no terminal at all.
    substituteInPlace ldisc.c \
      --replace-fail "if (term->supdup_mode)" \
                     "if (ldisc->term && ldisc->term->supdup_mode)"
    # The ITS/WAITS translator reads per-terminal charset state.
    substituteInPlace terminal.c \
      --replace-fail "translate_supdup_extended_ascii(unsigned long in)" \
                     "translate_supdup_extended_ascii(Terminal *term, unsigned long in)" \
      --replace-fail "translate_supdup_extended_ascii(c)" \
                     "translate_supdup_extended_ascii(term, c)"
    substituteInPlace unix/uxplink.c \
      --replace-fail "Usage: plink" "Usage: suppty-plink" \
      --replace-fail '"plink:' '"suppty-plink:'
    substituteInPlace unix/gtkwin.c \
      --replace-fail "pterm option summary:" "suppty option summary:"
    substituteInPlace unix/uxgss.c \
      --replace-fail '"libgssapi_krb5.so.2"' \
                     '"${lib.getLib krb5}/lib/libgssapi_krb5.so.2"'
  '';

  # Regenerate every Unix object list rather than the shipped Makefile.am.
  # mkfiles.pl requires charset/sbcsgen.pl from '.'; mkauto.sh is CRLF, so
  # run its autoreconf directly.  gtk-2.0.m4 provides AM_PATH_GTK_2_0.
  preConfigure = ''
    perl -I. mkfiles.pl
    export ACLOCAL_PATH="${lib.getDev gtk2}/share/aclocal''${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    autoreconf -i
  '';

  configureFlags = [ "--with-gtk=2" ];
  # Upstream configure adds -Werror; GTK 2 deprecations would fail it.
  makeFlags = [ "WARNINGOPTS=-Wall" ];
  buildFlags = [ "putty" "plink" ];
  enableParallelBuilding = true;

  postBuild = ''
    make -C doc putty.1 plink.1
  '';

  # Install only the terminal client and its command-line frontend, renamed to
  # avoid colliding with PuTTY.
  installPhase = ''
    runHook preInstall
    install -Dm755 putty $out/bin/suppty
    install -Dm755 plink $out/bin/suppty-plink
    sed -e 's/\\fBputty\\fP/\\fBsuppty\\fP/g' -e 's/^\.TH "putty"/.TH "suppty"/' \
      doc/putty.1 > suppty.1
    sed -e 's/\\fBplink\\fP/\\fBsuppty-plink\\fP/g' -e 's/^\.TH "plink"/.TH "suppty-plink"/' \
      -e 's/information on plink,/information on suppty-plink,/' \
      doc/plink.1 > suppty-plink.1
    install -Dm644 -t $out/share/man/man1 suppty.1 suppty-plink.1
    install -Dm644 -t $out/share/doc/pdp10-suppty LICENCE README
    runHook postInstall
  '';

  meta = {
    description = "SUPDUP-capable graphical and command-line host client based on PuTTY";
    longDescription = ''
      SUPPTY extends the PuTTY 0.66 host terminal client with the SUPDUP
      protocol and ITS/WAITS character sets.  The GTK 2 client is installed as
      suppty and the command-line frontend as suppty-plink.  For command-line
      SUPDUP, use suppty-plink supdup,HOST or a saved SUPDUP session; Plink
      forwards the display bytes without terminal emulation.
    '';
    homepage = "https://github.com/PDP-10/SUPPTY";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "suppty";
  };
}
