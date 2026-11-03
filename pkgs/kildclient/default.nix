{
  lib,
  stdenv,
  fetchurl,
  gettext,
  glib,
  gnutls,
  gtk3,
  gtkspell3,
  perl,
  perlPackages,
  pkg-config,
  wrapGAppsHook3,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "kildclient";
  version = "3.2.3";

  src = fetchurl {
    url = "mirror://sourceforge/kildclient/kildclient/${finalAttrs.version}/kildclient-${finalAttrs.version}.tar.gz";
    hash = "sha256-6BMpugSUPR33ArrTZNDYmNVCf4JenM9OtN5Aj6Qv/KE=";
  };

  nativeBuildInputs = [
    gettext
    # glib-compile-resources builds the GTK UI resource bundle.
    glib
    perl
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    glib
    gnutls
    gtk3
    gtkspell3
    perl
    zlib
  ];

  enableParallelBuilding = true;

  # src/timers.c calls log10, but kildclient_LDADD omits libm; configure
  # appends LIBS after LDADD on the final link line.
  env.LIBS = "-lm";

  # kildclient.pl, loaded by the embedded interpreter at startup, imports
  # JSON.  MSDP.pm ships with the client in share/kildclient.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PERL5LIB : "${perlPackages.makePerlPath [ perlPackages.JSON ]}")
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/kildclient
    test -f $out/share/kildclient/kildclient.pl
    test -f $out/share/kildclient/MSDP.pm
    grep -q '^use JSON;' $out/share/kildclient/kildclient.pl
    PERL5LIB=${perlPackages.makePerlPath [ perlPackages.JSON ]} \
      ${perl}/bin/perl -I$out/share/kildclient -c $out/share/kildclient/kildclient.pl
    runHook postInstallCheck
  '';

  meta = {
    description = "GTK MUD client with Perl scripting support";
    homepage = "https://www.kildclient.org/";
    license = lib.licenses.gpl2Plus;
    mainProgram = "kildclient";
    platforms = [ "x86_64-linux" ];
  };
})
