{
  lib,
  stdenv,
  fetchurl,
  libxdg_basedir,
  makeWrapper,
  ncurses,
  perl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "obumbrata";
  # Published release, tag 1.0.0 / 7drl-2014.
  version = "1.0.0";

  src = fetchurl {
    # Upstream does not serve HTTPS.
    url = "http://www.blackswordsonics.com/martin/obumbrata/obumbrata_${finalAttrs.version}.tar.gz";
    hash = "sha256-JT1iUNI3j+kfFeqS75ya1cf5Z7rad3juiVW7LI6srEc=";
  };

  nativeBuildInputs = [
    makeWrapper
    perl
  ];
  buildInputs = [
    libxdg_basedir
    ncurses
  ];

  postPatch = ''
    patchShebangs pobj_comp pmon_comp
    # The release joins PATCHVERS=0 to -std=gnu11.
    substituteInPlace Makefile \
      --replace-fail '$(PATCHVERS)-std=gnu11' '$(PATCHVERS) -std=gnu11'
    # Missing standard headers under modern libstdc++/glibc.
    substituteInPlace map.hh \
      --replace-fail '#include <deque>' $'#include <deque>\n#include <vector>'
    substituteInPlace log.cc \
      --replace-fail '#include <map>' $'#include <map>\n#include <string>'
    substituteInPlace rng.cc \
      --replace-fail '#include <time.h>' $'#include <time.h>\n#include <stdlib.h>'
    # Wide ncurses headers live directly under include; keep curses special
    # keys and ERR out of iscntrl's unsigned-char domain.
    substituteInPlace display-nc.cc \
      --replace-fail '<ncursesw/curses.h>' '<curses.h>' \
      --replace-fail '<ncursesw/panel.h>' '<panel.h>' \
      --replace-fail '#include <langinfo.h>' $'#include <langinfo.h>\n#include <ctype.h>' \
      --replace-fail 'if ((ch > 127))' 'if ((ch < 0) || (ch > 127))'
  '';

  # Bundled Perl script, not Autoconf.
  configurePhase = ''
    runHook preConfigure
    perl configure --prefix=$out --gamesdir=$out/libexec
    runHook postConfigure
  '';

  # Each Perl generator emits two files from one rule; build serially.
  enableParallelBuilding = false;

  makeFlags = [
    "DEVELOPMENT_CFLAGS=$(PRODUCTION_CFLAGS)"
    "DEVELOPMENT_CXXFLAGS=$(PRODUCTION_CXXFLAGS)"
    "DEVELOPMENT_LDFLAGS=$(COMMON_LDFLAGS)"
  ];

  # Saves use upstream libxdg-basedir HOME/XDG paths.
  postInstall = ''
    install -Dm644 -t $out/share/doc/obumbrata COPYING notes.txt
    makeWrapper $out/libexec/obumbrata $out/bin/obumbrata \
      --prefix TERMINFO_DIRS : ${ncurses}/share/terminfo
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/obumbrata
    test -f $out/share/man/man6/obumbrata.6.gz
    test -f $out/share/doc/obumbrata/COPYING
    runHook postInstallCheck
  '';

  meta = {
    description = "Shadow-realm terminal roguelike from the 2014 Seven Day Roguelike Challenge";
    homepage = "http://www.blackswordsonics.com/martin/obumbrata/";
    license = lib.licenses.bsd2;
    mainProgram = "obumbrata";
    platforms = [ "x86_64-linux" ];
  };
})
