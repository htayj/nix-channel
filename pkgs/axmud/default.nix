{
  lib,
  fetchFromGitHub,
  gobject-introspection,
  goocanvas_2,
  gtk3,
  openssh,
  perlPackages,
  wrapGAppsHook3,
  xvfb-run,
}:

let
  # Runtime Perl prerequisites from Makefile.PL; the rest are perl core.
  perlDeps = with perlPackages; [
    ArchiveExtract
    ArchiveZip
    FileCopyRecursive
    FileHomeDir
    FileShareDir
    FileShareDirInstall
    Glib
    GooCanvas2
    Gtk3
    IOSocketSSL
    IPCRun
    JSON
    MathRound
    NetOpenSSH
    RegexpIPv6
  ];
in
perlPackages.buildPerlPackage {
  pname = "axmud";
  version = "2.0.0";

  # v2.0.0 resolves to this release commit; pin the commit, not the tag.
  src = fetchFromGitHub {
    owner = "axcore";
    repo = "axmud";
    rev = "3dbbd963baa9555c10a0c7ae3e4b007f53f6585a";
    hash = "sha256-HJnBI3+8A2acHRIf9HTz0kdM/8XgM+WxLXK6OMTeNtA=";
  };

  postPatch = ''
    # MXP content can request network downloads. Keep the per-profile
    # preference, but default both download capabilities to off.
    substituteInPlace lib/Games/Axmud/Client.pm \
      --replace-fail "allowMxpLoadImageFlag       => TRUE" "allowMxpLoadImageFlag       => FALSE" \
      --replace-fail "allowMxpLoadSoundFlag       => TRUE" "allowMxpLoadSoundFlag       => FALSE"
    grep -qF "allowMxpLoadImageFlag       => FALSE" lib/Games/Axmud/Client.pm
    grep -qF "allowMxpLoadSoundFlag       => FALSE" lib/Games/Axmud/Client.pm

    # Upstream typo: '::' instead of '->' before the method name. Perl 5.42
    # rejects it ("Missing comma after first argument to return").
    substituteInPlace lib/Games/Axmud/Obj/File.pm \
      --replace-fail '$axmud::CLIENT::writeImproper(' '$axmud::CLIENT->writeImproper('
  '';

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook3
  ];

  buildInputs = [
    goocanvas_2
    gtk3
    perlPackages.PathTiny
  ];

  propagatedBuildInputs = perlDeps;

  postInstall = ''
    doc=$out/share/doc/axmud
    install -Dm644 -t $doc AUTHORS CHANGES COPYING COPYING.LESSER README.rst META.json
    install -Dm644 share/docs/COPYING $doc/docs-COPYING
    install -Dm644 share/help/COPYING $doc/help-COPYING
    install -Dm644 share/icons/COPYING $doc/icons-COPYING
    install -Dm644 share/images/COPYING $doc/images-COPYING
    install -Dm644 share/items/sounds/COPYING $doc/sounds-COPYING
    ln -s axmud.pl $out/bin/axmud
  '';

  # File::ShareDir locates the installed share data through @INC, and
  # Net::OpenSSH runs the ssh binary.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PERL5LIB : "$out/lib/perl5/site_perl:${perlPackages.makeFullPerlPath perlDeps}"
      --prefix PATH : "${lib.makeBinPath [ openssh ]}"
    )
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ xvfb-run ];
  installCheckPhase = ''
    runHook preInstallCheck

    site=$out/lib/perl5/site_perl/${perlPackages.perl.version}
    test -f $site/auto/share/dist/Games-Axmud/help/COPYING
    test -f $out/share/doc/axmud/sounds-COPYING
    grep -qF "allowMxpLoadImageFlag       => FALSE" $site/Games/Axmud/Client.pm
    grep -qF "allowMxpLoadSoundFlag       => FALSE" $site/Games/Axmud/Client.pm
    grep -qF '$axmud::CLIENT->writeImproper(' $site/Games/Axmud/Obj/File.pm
    grep -qa goocanvas $out/bin/axmud.pl
    grep -qa openssh $out/bin/axmud.pl

    # Private, disposable user state for every runtime check.
    export HOME=$TMPDIR/axmud-home
    export XDG_CONFIG_HOME=$TMPDIR/xdg/config XDG_CACHE_HOME=$TMPDIR/xdg/cache
    export XDG_DATA_HOME=$TMPDIR/xdg/data XDG_STATE_HOME=$TMPDIR/xdg/state
    export XDG_RUNTIME_DIR=$TMPDIR/xdg/runtime
    mkdir -p $HOME $XDG_CONFIG_HOME $XDG_CACHE_HOME $XDG_DATA_HOME $XDG_STATE_HOME
    mkdir -m 700 -p $XDG_RUNTIME_DIR

    # `use Gtk3 '-init'` opens a display at compile time.
    for prog in axmud.pl baxmud.pl; do
      xvfb-run -a -s '-screen 0 1024x768x24' \
        perl -I$site -c $out/bin/.$prog-wrapped
    done

    # Bounded headless start: Gtk3->main never returns, so the timeout is
    # the expected outcome; the client must have created its data tree
    # inside the disposable home.
    rc=0
    timeout 30 xvfb-run -a -s '-screen 0 1024x768x24' $out/bin/axmud </dev/null || rc=$?
    test "$rc" = 124
    test -d $HOME/axmud-data/data

    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical MUD client written in Perl and GTK3";
    homepage = "https://github.com/axcore/axmud";
    # Client GPL-3.0+; Games::Axmud/Axbasic shared code LGPL-3.0+; bundled
    # docs/help GFDL-1.3+; icons CC-BY-3.0; viewer image CC-BY-2.0; sounds
    # public domain. Notices are in share/doc/axmud.
    license = with lib.licenses; [
      gpl3Plus
      lgpl3Plus
      fdl13Plus
      cc-by-30
      cc-by-20
      publicDomain
    ];
    mainProgram = "axmud";
    platforms = [ "x86_64-linux" ];
  };
}
