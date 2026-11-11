{
  lib,
  stdenv,
  fetchFromGitHub,
  fpc,
  coreutils,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gearhead2";
  version = "0.701";

  # v0.701 (2017-12-03); upstream has no release tag for it.
  src = fetchFromGitHub {
    owner = "jwvhewitt";
    repo = "gearhead-2";
    rev = "415dee8d8730ef1ed8adfd741b1a2b2fa201c2e7";
    hash = "sha256-qbJTSIBzRJkKTbje/5J6zuuqyHw8GQh0OEkPysFSisA=";
  };

  # The Pascal sources use CRLF and the patches use LF, so normalize the
  # patched files first, then require an exact application.
  # xdg-config: read gearhead2.cfg from XDG_CONFIG_HOME and keep the
  #   positional directory for saves and the mission-giver report.
  # native-restore: resume a clock-mode save at the paused player input and
  #   keep empty or duplicate string attributes when loading.
  # The ASCII edition never reads image/ (portraits, sprites, fonts) or the
  # .obj meshes; drop them so they cannot reach the installed data.
  postPatch = ''
    sed -i 's/\r$//' gears.pp pcaction.pp arenaplay.pp gearutil.pp
    for p in ${./xdg-config.patch} ${./native-restore.patch}; do
      patch -p1 --fuzz=0 --no-backup-if-mismatch --input "$p"
    done
    rm -r image gamedata/*.obj
  '';

  nativeBuildInputs = [ fpc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir -p build/units
    fpc -dASCII -O2 -g- -FUbuild/units -FEbuild -obuild/gearhead2-real gearhead2.pas
    runHook postBuild
  '';

  # The game reads design, gamedata, series and doc relative to its working
  # directory. Its only argument is the directory for savegame/ and reports.
  installPhase = ''
    runHook preInstall

    data=$out/share/gearhead2
    doc=$out/share/doc/gearhead2

    install -Dm755 build/gearhead2-real $out/libexec/gearhead2-real

    mkdir -p $data
    cp -r design gamedata series doc $data/

    install -Dm644 -t $doc license.txt readme.txt history.txt doc/Credits.txt

    # The Free Pascal runtime is linked into the game: ship its Library GPL
    # and linking exception from the compiler's source.
    mkdir -p $doc/fpc-rtl
    tar -xzf ${fpc.src} -C $doc/fpc-rtl --strip-components=1 \
      fpcbuild-${fpc.version}/install/doc/COPYING \
      fpcbuild-${fpc.version}/fpcsrc/rtl/COPYING.FPC
    mv $doc/fpc-rtl/install/doc/COPYING $doc/fpc-rtl/fpcsrc/rtl/COPYING.FPC $doc/fpc-rtl/
    rm -r $doc/fpc-rtl/install $doc/fpc-rtl/fpcsrc

    cat > $doc/SOURCE-PROVENANCE <<EOF
    GearHead2 v${finalAttrs.version} (ASCII)
    Upstream: https://github.com/jwvhewitt/gearhead-2
    Commit: ${finalAttrs.src.rev}
    Source NAR hash: ${finalAttrs.src.outputHash}

    LGPL-2.1-or-later: Pascal code and the text-only design, gamedata, series
    and doc trees, per readme.txt, license.txt and the gearhead2.pas header.
    Excluded and not installed: image/ (PNG/JPEG portraits and sprites, an
    XCF file and two bundled Bitstream Vera fonts), gamedata/*.obj meshes and
    the SDL front-end sources.

    Patches from the htayj Guix channel (commit 2714823b): xdg-config keeps
    gearhead2.cfg under XDG_CONFIG_HOME; native-restore continues a paused
    clock-mode turn and preserves saved string attributes.

    Free Pascal RTL ${fpc.version}: fpc-rtl/COPYING and fpc-rtl/COPYING.FPC,
    Library GPL version 2 or later with the static linking exception.
    EOF

    mkdir -p $out/bin
    cat > $out/bin/gearhead2 <<EOF
    #!${runtimeShell}
    set -eu
    if [ "\$#" -gt 1 ]; then
      echo 'usage: gearhead2 [STATE-DIRECTORY]' >&2
      exit 2
    fi
    case "\''${XDG_CONFIG_HOME:-}" in
      /*) config=\$XDG_CONFIG_HOME ;;
      *) config=\''${HOME:?HOME must be set}/.config ;;
    esac
    if [ "\$#" -eq 1 ]; then
      state=\$1
    else
      case "\''${XDG_STATE_HOME:-}" in
        /*) state=\$XDG_STATE_HOME/gearhead2 ;;
        *) state=\''${HOME:?HOME must be set}/.local/state/gearhead2 ;;
      esac
    fi
    case "\$state" in
      /*) ;;
      *) state=\$PWD/\$state ;;
    esac
    umask 077
    ${coreutils}/bin/mkdir -p -- "\$config/gearhead2" "\$state"
    export XDG_CONFIG_HOME=\$config
    cd $data
    exec $out/libexec/gearhead2-real "\$state"
    EOF
    chmod 555 $out/bin/gearhead2

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/gearhead2/gamedata/sdl_colors.txt
    test -f $out/share/gearhead2/series/ANPCdefault.txt
    ! find $out/share/gearhead2 -type f ! -name '*.txt' | grep -q .
    status=0
    $out/bin/gearhead2 one two 2> usage.txt || status=$?
    test "$status" -eq 2
    grep -qx 'usage: gearhead2 \[STATE-DIRECTORY\]' usage.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "Mecha role-playing roguelike with an ASCII interface";
    longDescription = ''
      GearHead2 is a science-fiction roguelike role-playing game with mecha
      combat, character development and generated adventures.  This package
      builds the ASCII edition with Free Pascal and ships only the text game
      data.  gearhead2.cfg lives in $XDG_CONFIG_HOME/gearhead2; saved games
      live in $XDG_STATE_HOME/gearhead2, ~/.local/state/gearhead2, or the
      directory given as the only argument.
    '';
    homepage = "https://github.com/jwvhewitt/gearhead-2";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gearhead2";
  };
})
