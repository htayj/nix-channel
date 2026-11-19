# SoundThread run from source on the Godot 4.4 engine its project declares.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  coreutils,
  godot_4_4,
  runtimeShell,
}:

let
  # The bundled BravuraText_SoundThread.otf reports Bravura Text 1.393.
  # Upstream has no tag for that version; this commit bumped the font to it.
  bravuraCommit = "3df1714e6f9d522a8d2b6ee6888fa3e68e71199d";
  bravuraUrl = path:
    "https://raw.githubusercontent.com/steinbergmedia/bravura/${bravuraCommit}/redist/${path}";
  bravuraText = fetchurl {
    name = "BravuraText-1.393.otf";
    url = bravuraUrl "otf/BravuraText.otf";
    hash = "sha256-vVsdCkOFPjLqoIUa/po35ZZ/iBUycCJYkMMq5z0qSUI=";
  };
  bravuraLicense = fetchurl {
    name = "Bravura-OFL.txt";
    url = bravuraUrl "OFL.txt";
    hash = "sha256-wkkpvnAoAmpl7oiU2h48NtKkzM4FSNm6i6ZFCfRjGe4=";
  };
  # Work Sans tag v1.40, whose WorkSans-Regular.otf is the bundled file.
  workSansLicense = fetchurl {
    name = "WorkSans-OFL.txt";
    url = "https://raw.githubusercontent.com/weiweihuanghuang/Work-Sans/63e708fff9c89a0739c2d6251c835236ea58924b/LICENSE.txt";
    hash = "sha256-4wbqny46LAjqmiQgWJ9vByJCpOSQpslRhNjxFALvJRA=";
  };

  engine = lib.getExe godot_4_4;
in
stdenvNoCC.mkDerivation {
  pname = "soundthread";
  # Nine commits after tag v0.4.0-beta.
  version = "0.4.0-beta-unstable-2026-01-30";

  src = fetchFromGitHub {
    owner = "j-p-higgins";
    repo = "SoundThread";
    rev = "a33198a84fa44d8ddc1ea7469653cbe0906eb3c5";
    hash = "sha256-BWcMCISr5yjQ5qDj/huVo1rSw53Fn3R1bHH72F2pQWc=";
  };

  # The bundled font is a modified Bravura Text that keeps the OFL reserved
  # name; the unmodified font of the same version, which maps every code point
  # the bundled one does, takes its place.  The channel selects the version,
  # so the release request to GitHub at startup goes.
  postPatch = ''
    install -m644 ${bravuraText} theme/BravuraText_SoundThread.otf
    substituteInPlace scenes/Nodes/check_for_updates.gd --replace-fail \
      'request(GITHUB_API_URL, ["User-Agent: SoundThread0"])' \
      'pass # Automatic release check disabled by the channel.'
  '';

  dontConfigure = true;
  dontBuild = true;

  # The import the launcher performs at each start, on a disposable copy.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    cp -R . $TMPDIR/soundthread-check
    ${engine} --headless --audio-driver Dummy \
      --path $TMPDIR/soundthread-check --editor --import
    ls $TMPDIR/soundthread-check/.godot/imported/BravuraText_SoundThread.otf-*.fontdata
    ls $TMPDIR/soundthread-check/.godot/imported/WorkSans-Regular.otf-*.fontdata
    rm -r $TMPDIR/soundthread-check
    runHook postCheck
  '';

  # Godot writes its import cache beside the project, so the launcher imports
  # and runs a private copy and removes it on exit.
  installPhase = ''
    runHook preInstall

    data=$out/share/soundthread
    doc=$out/share/doc/soundthread
    mkdir -p $data $out/bin
    cp -R . $data/
    install -Dm444 -t $doc LICENSE
    install -Dm444 ${bravuraLicense} $doc/Bravura-OFL.txt
    install -Dm444 ${workSansLicense} $doc/WorkSans-OFL.txt

    cat > $out/bin/soundthread <<EOF
    #!${runtimeShell}
    set -eu
    project=\$(${coreutils}/bin/mktemp -d "\''${TMPDIR:-/tmp}/soundthread.XXXXXXXX")
    trap '${coreutils}/bin/rm -rf -- "\$project"' EXIT HUP INT TERM
    ${coreutils}/bin/cp -R --no-preserve=mode "$data/." "\$project/"
    ${engine} --headless --audio-driver Dummy --path "\$project" --editor --import \\
      >"\$project/import.log" 2>&1 || { ${coreutils}/bin/cat "\$project/import.log" >&2; exit 1; }
    ${engine} --path "\$project" "\$@"
    EOF
    chmod 555 $out/bin/soundthread

    runHook postInstall
  '';

  # The launcher end to end: the engine is the 4.4 the project declares, and
  # the main scene loads and runs headless without script or resource errors.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home
    mkdir -p $HOME
    cmp ${bravuraText} $out/share/soundthread/theme/BravuraText_SoundThread.otf
    $out/bin/soundthread --version | grep -F 4.4.
    $out/bin/soundthread --headless --audio-driver Dummy --quit-after 20 > run.log 2>&1 \
      || { cat run.log; exit 1; }
    cat run.log
    if grep -E 'SCRIPT ERROR|Parse Error|Failed loading resource' run.log; then
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Node-based audio interface for the Composers Desktop Project";
    longDescription = ''
      SoundThread is a Godot application for connecting audio files and CDP
      commands in a graph.  The source project is copied to disposable
      writable state for imports, leaving its installed files immutable.  CDP
      is an optional external user integration and is neither bundled nor
      configured by this package.
    '';
    homepage = "https://github.com/j-p-higgins/SoundThread";
    license = with lib.licenses; [ mit ofl ];
    mainProgram = "soundthread";
    platforms = [ "x86_64-linux" ];
  };
}
