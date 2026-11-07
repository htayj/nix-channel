{
  lib,
  stdenv,
  fetchurl,
  fpc,
  unzip,
  SDL,
  SDL_image,
  SDL_ttf,
  libX11,
  ttf-bitstream-vera,
  coreutils,
  runtimeShell,
}:

let
  runtimeLibs = [
    SDL
    SDL_image
    SDL_ttf
    libX11
  ];
  libDirs = map (pkg: "${lib.getLib pkg}/lib") runtimeLibs;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "dungeon-monkey-unlimited";
  version = "1.001";

  src = fetchurl {
    url = "https://downloads.sourceforge.net/project/dmonkey/v1.000%20Series/DungeonMonkeyUnlimited-${finalAttrs.version}-source.zip";
    hash = "sha256-93LtDXRXevVfVKk5y0VuWqVHwEQ7XtHVnt6/fhIw6dw=";
  };

  sourceRoot = "DMU";

  nativeBuildInputs = [
    fpc
    unzip
  ];
  buildInputs = runtimeLibs;

  dontConfigure = true;

  # The archive holds Free Pascal sources and no build system.  The SDL units
  # shipped with fpc link libSDL, libSDL_image and libSDL_ttf at link time;
  # fpc calls ld directly, so library paths and rpaths are passed explicitly.
  buildPhase = ''
    runHook preBuild
    mkdir -p build/units
    fpc -O2 -g- -dLINUX -Fu. \
      -Fu${fpc}/lib/fpc/${fpc.version}/units/x86_64-linux/sdl \
      -FUbuild/units -FEbuild \
      ${lib.concatMapStringsSep " " (d: "-Fl${d} -k-L${d} -k-rpath=${d}") libDirs} \
      -k-lSDL -k-lSDL_image -k-lSDL_ttf \
      -obuild/dungeon-monkey-unlimited-real dmu.pas
    runHook postBuild
  '';

  # The game resolves gamedata/, image/, savegame/ and config.cfg relative to
  # its working directory and rewrites config.cfg on exit, so the launcher runs
  # it from a per-user data directory that links the read-only game data.
  installPhase = ''
    runHook preInstall
    data=$out/share/dungeon-monkey-unlimited
    doc=$out/share/doc/dungeon-monkey-unlimited
    install -Dm755 build/dungeon-monkey-unlimited-real \
      $out/libexec/dungeon-monkey-unlimited-real
    mkdir -p $data/image $doc
    cp -r gamedata $data/gamedata
    # Sprite templates and convert.png are editor inputs the game never loads.
    for f in image/*.png; do
      case "$(basename "$f")" in
        template_*|convert.png) ;;
        *) install -m644 "$f" $data/image/ ;;
      esac
    done
    install -m644 image/VeraBd.ttf $data/image/
    install -m644 -t $doc license.txt readme.txt credits.txt
    cp -r doc $doc/upstream-doc
    # VeraBd.ttf is the unmodified Bitstream Vera Bold font.
    tar -xjOf ${ttf-bitstream-vera.src} ttf-bitstream-vera-1.10/COPYRIGHT.TXT \
      > $doc/Bitstream-Vera-COPYRIGHT.TXT
    cat > $doc/THIRD-PARTY-NOTICES.txt <<'EOF'
    Dungeon Monkey Unlimited third-party materials

    Code, gamedata and documentation: Joseph Hewitt, LGPL-2.1-or-later.
    The complete LGPL 2.1 text is in license.txt; source headers permit later
    versions.

    David E. Gervais tile graphics
    Most tile graphics are by David E. Gervais and are available under the
    Creative Commons Attribution 3.0 license. Credit David E. Gervais when
    redistributing these graphics.
    Tile license source: http://pousse.rapiere.free.fr/tome/tome-tiles.htm
    https://creativecommons.org/licenses/by/3.0/

    RLTiles
    Part of (or All) the graphic tiles used in this program is the public
    domain roguelike tileset "RLTiles". Some of the tiles have been modified
    by Joseph Hewitt.
    You can find the original tileset at: http://rltiles.sf.net

    Bitstream Vera
    The used VeraBd.ttf is distributed under the Bitstream Vera license.
    The complete, exact license text is in Bitstream-Vera-COPYRIGHT.TXT in
    this directory.
    EOF
    mkdir -p $out/bin
    launcher=$out/bin/dungeon-monkey-unlimited
    cat > $launcher <<'EOF'
    #!@shell@
    set -eu
    real=@out@/libexec/dungeon-monkey-unlimited-real
    data=@out@/share/dungeon-monkey-unlimited
    state="''${XDG_DATA_HOME:-''${HOME:?HOME or XDG_DATA_HOME must be set}/.local/share}/dungeon-monkey-unlimited"
    @coreutils@/bin/mkdir -p "$state/savegame"
    for resource in gamedata image; do
      if test ! -e "$state/$resource"; then
        @coreutils@/bin/ln -s "$data/$resource" "$state/$resource"
      fi
    done
    cd "$state"
    exec "$real" "$@"
    EOF
    substituteInPlace $launcher \
      --replace-fail @shell@ ${runtimeShell} \
      --replace-fail @out@ $out \
      --replace-fail @coreutils@ ${coreutils}
    chmod 555 $launcher
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    real=$out/libexec/dungeon-monkey-unlimited-real
    test -x $real
    ! ldd $real | grep -q 'not found'
    for l in libSDL libSDL_image libSDL_ttf; do ldd $real | grep -q "$l"; done
    data=$out/share/dungeon-monkey-unlimited
    test -d $data/gamedata
    test -f $data/image/VeraBd.ttf
    ! ls $data/image | grep -q -e '^template_' -e '^convert\.png$'
    grep -q 'Bitstream' $out/share/doc/dungeon-monkey-unlimited/Bitstream-Vera-COPYRIGHT.TXT
    grep -q 'GNU Lesser General' $out/share/doc/dungeon-monkey-unlimited/license.txt
    ${runtimeShell} -n $out/bin/dungeon-monkey-unlimited
    ! grep -q '@[a-z]*@' $out/bin/dungeon-monkey-unlimited
    grep -qF 'state="''${XDG_DATA_HOME:-''${HOME:?' $out/bin/dungeon-monkey-unlimited
    runHook postInstallCheck
  '';

  meta = {
    description = "SDL tactics role-playing game with procedurally generated campaigns";
    longDescription = ''
      Dungeon Monkey Unlimited is a Pascal and SDL tactics role-playing game
      from the original Dungeon Monkey lineage.  It generates a fantasy
      campaign, map and encounters locally.  The launcher keeps saves and
      config.cfg in $XDG_DATA_HOME/dungeon-monkey-unlimited.
    '';
    homepage = "https://sourceforge.net/projects/dmonkey/";
    license = with lib.licenses; [
      lgpl21Plus
      cc-by-30
      publicDomain
      bitstreamVera
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-monkey-unlimited";
  };
})
