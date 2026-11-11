{
  lib,
  stdenv,
  fetchurl,
  fpc,
  coreutils,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gearhead";
  version = "1.310";

  # v1.310 (2019-02-07), the peeled release commit.
  src = fetchurl {
    url = "https://codeload.github.com/jwvhewitt/gearhead-1/tar.gz/4314041f9e703e356807a9d17e613aae09289df4";
    name = "gearhead-${finalAttrs.version}.tar.gz";
    hash = "sha256-ovEg8AbXLu+UCOVY3QpWnwoEwGy/CkRwY6k0lDpBmvY=";
  };

  patches = [
    # Save edited maps in the user's configuration directory, not in the
    # immutable Series directory.
    ./writable-maps.patch
    # Resume an initialized combat scene at the saved player input.
    ./resume.patch
  ];
  # The Pascal sources use CRLF line endings.
  patchFlags = [
    "-p1"
    "--binary"
  ];

  # This is the ASCII edition: drop the graphical assets, bundled fonts and
  # the SDL and alternate box-drawing front ends.
  postPatch = ''
    rm -r Image sdlgfx.pp sdlinfo.pp sdlmap.pp sdlmenus.pp cosplay.pas \
      xterm-boxdrawing GameData/sdl_colors.txt
  '';

  nativeBuildInputs = [ fpc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir -p build/units
    fpc -O2 -g- -FUbuild/units -FEbuild -obuild/gharena gharena.pas
    runHook postBuild
  '';

  # The game looks up Design, GameData, Series and doc relative to its
  # working directory and takes the directory holding gharena.cfg, SaveGame
  # and edited maps as its only argument.
  installPhase = ''
    runHook preInstall

    data=$out/share/gearhead
    doc=$out/share/doc/gearhead

    install -Dm755 build/gharena $out/libexec/gharena

    mkdir -p $data
    cp -r Design GameData Series doc $data/

    install -Dm644 -t $doc license.txt readme.md history.txt compiling.txt \
      doc/Credits.txt gharena.pas

    # The Free Pascal runtime is linked into gharena: ship its Library GPL
    # and linking exception from the compiler's source.
    mkdir -p $doc/fpc-rtl
    tar -xzf ${fpc.src} -C $doc/fpc-rtl --strip-components=1 \
      fpcbuild-${fpc.version}/install/doc/COPYING \
      fpcbuild-${fpc.version}/fpcsrc/rtl/COPYING.FPC
    mv $doc/fpc-rtl/install/doc/COPYING $doc/fpc-rtl/fpcsrc/rtl/COPYING.FPC $doc/fpc-rtl/
    rm -r $doc/fpc-rtl/install $doc/fpc-rtl/fpcsrc

    cat > $doc/SOURCE-PROVENANCE <<EOF
    GearHead: Arena v${finalAttrs.version} (ASCII)
    Upstream: https://github.com/jwvhewitt/gearhead-1
    Commit: 4314041f9e703e356807a9d17e613aae09289df4
    Archive SHA-256: a2f120f006d72eef9408e558dd0a569f0a04c06cbf0a447063a934943a419af6

    LGPL-2.1-or-later: Pascal code and text-only Design, GameData, Series and doc.
    See the readme.md distribution statement, the gharena.pas copyright header
    and license.txt.  Image (including all bundled fonts), the SDL sources and
    xterm-boxdrawing are excluded.

    Patches from the htayj Guix channel (commit 2714823b): writable-maps saves
    user maps next to gharena.cfg; resume continues a saved combat scene.

    Free Pascal RTL ${fpc.version}: fpc-rtl/COPYING and fpc-rtl/COPYING.FPC,
    Library GPL version 2 or later with the static linking exception.
    EOF

    mkdir -p $out/bin
    cat > $out/bin/gearhead <<EOF
    #!${runtimeShell}
    set -eu
    if [ "\$#" -gt 1 ]; then
      echo 'usage: gearhead [CONFIG-DIRECTORY]' >&2
      exit 2
    fi
    if [ "\$#" -eq 1 ]; then
      state=\$1
    else
      case "\''${XDG_STATE_HOME:-}" in
        /*) state=\$XDG_STATE_HOME/gearhead ;;
        *) state=\''${HOME:?HOME must be set}/.local/state/gearhead ;;
      esac
    fi
    case "\$state" in
      /*) ;;
      *) state=\$PWD/\$state ;;
    esac
    umask 077
    ${coreutils}/bin/mkdir -p -- "\$state"
    cd $data
    exec $out/libexec/gharena "\$state"
    EOF
    chmod 555 $out/bin/gearhead

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/gearhead/Series/ADV_FederatedTerritories.txt
    status=0
    $out/bin/gearhead one two 2> usage.txt || status=$?
    test "$status" -eq 2
    grep -qx 'usage: gearhead \[CONFIG-DIRECTORY\]' usage.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Mecha role-playing roguelike with an ASCII interface";
    longDescription = ''
      GearHead: Arena is a science-fiction roguelike role-playing game with
      procedural campaigns, character development and mecha combat.  This
      package builds the ASCII edition with Free Pascal and ships only the
      text game data.  Configuration, saved games and edited maps live in
      $XDG_STATE_HOME/gearhead, ~/.local/state/gearhead, or the directory
      given as the only argument.
    '';
    homepage = "https://www.gearheadrpg.com/";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gearhead";
  };
})
