{
  lib,
  stdenv,
  fetchFromGitHub,
  ncurses,
  xxd,
  coreutils,
  runtimeShell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "diabaig";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "conornally";
    repo = "diabaig";
    rev = "b90d35847070d3de27d4656b3316e0e932884b25"; # tag diabaig-v1.0.1
    hash = "sha256-t+FCdkZHRFMIAYwp25pbgW/UDikJEZKMah7ZvYZhgN8=";
  };

  nativeBuildInputs = [ xxd ];
  buildInputs = [ ncurses ];

  # The generated-source rules rely on an echo that interprets "\n", which
  # bash's builtin does not; write the same text with printf.
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail '@echo "#define DATAHEADER_H\n" >> $@' \
                     "@printf '%s\\n\\n' '#define DATAHEADER_H' >> \$@" \
      --replace-fail '@echo "\n#endif//DATAHEADER_H" >> $@' \
                     "@printf '\\n%s\\n' '#endif//DATAHEADER_H' >> \$@" \
      --replace-fail '@echo "#include \"data_embedded.h\"\n">> $@' \
                     "@printf '%s\\n\\n' '#include \"data_embedded.h\"' >> \$@"
  '';

  dontConfigure = true;
  enableParallelBuilding = true;

  # Upstream uses empty-parameter prototypes such as c_inroom() called with an
  # argument, which C23 rejects.
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "PLATFORM=linux"
  ];
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 build/linux/diabaig $out/libexec/diabaig/diabaig
    install -Dm644 -t $out/share/doc/diabaig LICENSE docs/guide.txt res/credits.txt
    sed 's/Version: VERSION/Version: ${finalAttrs.version}/' docs/README.md \
      > $out/share/doc/diabaig/README.md
    mkdir -p $out/share/man/man6
    sed 's/@VERSION@/${finalAttrs.version}/' docs/debian/diabaig.6 \
      > $out/share/man/man6/diabaig.6
    mkdir -p $out/bin
    cat > $out/bin/diabaig <<EOF
    #!${runtimeShell}
    set -eu
    state="\''${XDG_STATE_HOME:-\''${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}/diabaig"
    ${coreutils}/bin/mkdir -p -- "\$state/save"
    export TERM="\''${TERM:-xterm-256color}"
    export TERMINFO_DIRS="${ncurses}/share/terminfo\''${TERMINFO_DIRS:+:\$TERMINFO_DIRS}"
    cd -- "\$state"
    exec $out/libexec/diabaig/diabaig "\$@"
    EOF
    chmod 555 $out/bin/diabaig
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/libexec/diabaig/diabaig
    grep -qF "MIT License" $out/share/doc/diabaig/LICENSE
    grep -qF '#define DATAHEADER_H' build/data_embedded.h
    if grep -qF '\n' build/data_embedded.h; then exit 1; fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Traditional turn-based ASCII roguelike";
    longDescription = ''
      Diabaig is a traditional turn-based terminal roguelike with game text
      embedded at build time.  The launcher keeps configuration, saves and the
      hall of fame in $XDG_STATE_HOME/diabaig, falling back to
      ~/.local/state/diabaig.
    '';
    homepage = "https://github.com/conornally/diabaig";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "diabaig";
  };
})
