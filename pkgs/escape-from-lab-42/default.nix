{ lib, stdenv, fetchurl, unzip, fbc, patchelf
, libx11, libxext, libxpm, libxrandr, libxrender, ncurses }:

stdenv.mkDerivation {
  pname = "escape-from-lab-42";
  version = "0.2";

  # Upstream ships the BASIC source inside its Windows release archive.
  src = fetchurl {
    url = "https://users.freebasic-portal.de/rdc/programs/lab4202win.zip";
    hash = "sha256-C18DrDEKjvWxgLm09d/0pWQnfEnxFxcDUoT2tOTPl40=";
  };

  # The archive has several top-level entries; keep the root documents.
  unpackCmd = "unzip -q $curSrc -d source";

  nativeBuildInputs = [ unzip fbc patchelf ];
  buildInputs = [ libx11 libxext libxpm libxrandr libxrender ncurses ];

  # fbc's generated C fails under -Werror=format-security; nixpkgs' own
  # fbc derivation disables the same hardening flag.
  hardeningDisable = [ "format" ];

  postPatch = ''
    rm lab42.exe
    mkdir original-source
    cp src/*.bas src/*.bi original-source/

    # FreeBASIC 1.10 reserves BOOLEAN and predefines TRUE/FALSE as -1/0.
    # Rename the game's own 1/0 enum to keep its semantics.
    for f in lab42.bas labdata.bi labutils.bi labmap.bi labchar.bi; do
      sed -i -E \
        -e 's/\<[Bb][Oo][Oo][Ll][Ee][Aa][Nn]\>/lab42_boolean/g' \
        -e 's/\<[Bb][Oo][Oo][Ll]\>/lab42_bool/g' \
        -e 's/\<[Tt][Rr][Uu][Ee]\>/LAB42_TRUE/g' \
        -e 's/\<[Ff][Aa][Ll][Ss][Ee]\>/LAB42_FALSE/g' \
        src/$f
    done

    # Unix Timer returns epoch seconds; Single loses sub-second precision
    # at that magnitude.  Widen timer storage only.
    substituteInPlace src/labdata.bi \
      --replace-fail 'Dim As Single tdd = Timer' 'Dim As Double tdd = Timer' \
      --replace-fail 'zomtime As Single' 'zomtime As Double'
    substituteInPlace src/labutils.bi \
      --replace-fail 'Dim As Single mt' 'Dim As Double mt'
    substituteInPlace src/labmap.bi \
      --replace-fail 'Dim As Single tdiff' 'Dim As Double tdiff'
  '';

  # Upstream used "-s gui" and a Windows resource; neither applies to X11.
  buildPhase = ''
    runHook preBuild
    cd src
    fbc lab42.bas -x escape-from-lab-42
    # fbc hardcodes the FHS dynamic linker.
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      escape-from-lab-42
    cd ..
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 src/escape-from-lab-42 $out/bin/escape-from-lab-42
    doc=$out/share/doc/escape-from-lab-42
    install -Dm644 -t $doc readme42.txt changelog42.txt font_read_this.txt
    install -Dm644 -t $doc/source original-source/*
    # This 8x8 font comes from FreeBASIC's gfxlib2 (LGPL).
    install -Dm644 -t $doc/source ${fbc.src}/src/gfxlib2/gfxdata/fnt08x08.fnt
    # readme42.txt grants an unversioned GPL; ship GPLv2 text.
    install -Dm644 ${fbc.src}/doc/gpl.txt $doc/GPL-2.txt
    # The binary statically links FreeBASIC's runtime and gfx libraries:
    # LGPL text plus readme.txt's static linking exception.
    install -Dm644 -t $doc/freebasic-runtime \
      ${fbc.src}/doc/lgpl.txt ${fbc.src}/readme.txt
    runHook postInstall
  '';

  meta = {
    description = "Graphical roguelike escape from a zombie laboratory";
    longDescription = ''
      Escape From Lab 42 is a graphical roguelike by Richard D. Clark.  The
      player must escape a research laboratory overrun by zombies within 60
      minutes.  This package builds the original 0.2 FreeBASIC source as a
      native X11 program.  An optional end-of-game report is written to the
      current directory.
    '';
    homepage = "https://users.freebasic-portal.de/rdc/";
    license = with lib.licenses; [ gpl1Plus lgpl2Plus ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "escape-from-lab-42";
  };
}
