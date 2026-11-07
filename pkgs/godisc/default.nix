{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
  tmux,
  socat,
}:

buildGoModule (finalAttrs: {
  pname = "godisc";
  version = "0-unstable-2018-01-25";

  src = fetchFromGitHub {
    owner = "DavidSatimeWallin";
    repo = "godisc";
    rev = "47a9163d588faf165f461bd15bf7d7c20bbee092";
    hash = "sha256-2whphYUsH6hR1jhxI7AZu1lmygL1qF9It8hP7Bjf+LE=";
  };

  # The checkout predates Go modules.  go.mod and go.sum are channel-owned:
  # ziutek/telnet replaces the vanished stesla/gotelnet as in Guix, and
  # go-linenoise stays on the v2.0.0 API godisc uses.  lib/ is an unused web
  # front end whose gin and melody imports would otherwise need vendoring.
  vendorHash = "sha256-jmRVenwPU9NSwOPbWEm14nQoT+eO+A9duVK3ljo1FcU=";

  postPatch = ''
    rm -r lib
    cp ${./go.mod} go.mod
    cp ${./go.sum} go.sum

    substituteInPlace godisc.go \
      --replace-fail '"github.com/stesla/gotelnet"' '"github.com/ziutek/telnet"' \
      --replace-fail 'conn                gotelnet.Conn' 'conn                *telnet.Conn' \
      --replace-fail 'gotelnet.Dial(hostname)' 'telnet.Dial("tcp", hostname)' \
      --replace-fail 'goDiscCfgDir := usr.HomeDir + "/.config/godisc"' \
        $'homeDir := os.Getenv("HOME")\n\tif homeDir == "" {\n\t\thomeDir = usr.HomeDir\n\t}\n\tgoDiscCfgDir := os.Getenv("GODISC_CONFIG_DIR")\n\tif goDiscCfgDir == "" {\n\t\tgoDiscCfgDir = homeDir + "/.config/godisc"\n\t}' \
      --replace-fail 'os.Mkdir(goDiscCfgDir, 0770)' 'os.MkdirAll(goDiscCfgDir, 0770)' \
      --replace-fail $'\tcacheClubNames()' \
        $'\n\tif os.Getenv("GODISC_SKIP_WEB_CACHE") != "1" {\n\t\tcacheClubNames()\n\t}' \
      --replace-fail 'func main() {' \
        $'func main() {\n\tif len(os.Args) > 1 && os.Args[1] == "--version" {\n\t\tfmt.Println("godisc ${finalAttrs.version}")\n\t\treturn\n\t}\n\tif len(os.Args) > 1 && os.Args[1] == "--help" {\n\t\tfmt.Println("usage: godisc [HOST PORT]")\n\t\treturn\n\t}\n\tif len(os.Args) >= 3 {\n\t\tport, parseErr := strconv.Atoi(os.Args[2])\n\t\tif parseErr != nil {\n\t\t\tlog.Fatal(parseErr)\n\t\t}\n\t\tconnections = []Connection{{Host: os.Args[1], Port: port}}\n\t}' \
      --replace-fail 'go readKeyboardInput(conn)' \
        $'if os.Getenv("GODISC_NONINTERACTIVE") != "1" {\n\t\tgo readKeyboardInput(conn)\n\t}'
  '';

  subPackages = [ "." ];

  # go-linenoise wraps the bundled C linenoise through cgo.
  env.CGO_ENABLED = "1";
  ldflags = [ "-s" "-w" ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # tmux layout with chat and experience log panes.
    install -Dm755 launch-godisc.sh $out/bin/godisc-tmux
    substituteInPlace $out/bin/godisc-tmux \
      --replace-fail '#!/bin/bash' '#!${bash}/bin/bash' \
      --replace-fail 'SESSION=$USER' 'SESSION=''${GODISC_TMUX_SESSION:-''${USER:-godisc}}' \
      --replace-fail 'CONFDIR="/home/$SESSION/.config/godisc"' \
        'CONFDIR="''${GODISC_CONFIG_DIR:-''${HOME:-/tmp}/.config/godisc}"' \
      --replace-fail 'mkdir $CONFDIR' 'mkdir -p "$CONFDIR"' \
      --replace-fail 'tail -f /home/$SESSION/.config/godisc/tellChat.log' 'tail -f \"$CONFDIR/tellChat.log\"' \
      --replace-fail 'tail -f /home/$SESSION/.config/godisc/xp.log' 'tail -f \"$CONFDIR/xp.log\"' \
      --replace-fail '/usr/local/bin/godisc discworld.starturtle.net 4242' \
        "$out/bin/godisc \''${GODISC_HOST:-discworld.starturtle.net} \''${GODISC_PORT:-4242}"
    wrapProgram $out/bin/godisc-tmux \
      --prefix PATH : $out/bin:${lib.makeBinPath [ tmux coreutils ]}

    doc=$out/share/doc/godisc
    install -Dm644 LICENSE README.md alias.list highlight.list -t $doc
    # Preserve the notices of every vendored module.
    (cd vendor && find . -type f \( -name 'LICENSE*' -o -name 'license*' \
        -o -name 'COPYING*' -o -name 'NOTICE*' -o -name PATENTS \) \
      -exec install -Dm644 {} $doc/modules/{} \;)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ socat ];
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/home GODISC_SKIP_WEB_CACHE=1 GODISC_NONINTERACTIVE=1
    $out/bin/godisc --version | grep -Fx "godisc ${finalAttrs.version}"
    $out/bin/godisc --help | grep -F 'usage: godisc [HOST PORT]'
    test -d $HOME/.config/godisc

    # Offline protocol check: a loopback server greets once; the client loop
    # never exits on its own, so stop it with timeout.  The sandbox has no
    # /bin/sh, so socat runs an explicit bash script.
    printf '%s\n' 'printf "Welcome to godisc-smoke\r\n"' 'sleep 3' > $TMPDIR/greet.sh
    socat TCP-LISTEN:42420,bind=127.0.0.1,reuseaddr \
      EXEC:"${bash}/bin/bash $TMPDIR/greet.sh" &
    server=$!
    sleep 1
    status=0
    timeout 4 $out/bin/godisc 127.0.0.1 42420 > $TMPDIR/out 2>&1 || status=$?
    kill $server 2>/dev/null || true
    test "$status" = 124
    grep -F 'Welcome to godisc-smoke' $TMPDIR/out
    grep -F 'Welcome to godisc-smoke' $HOME/.config/godisc/clog
    if grep -F starturtle $TMPDIR/out; then exit 1; fi

    bash -n $out/bin/.godisc-tmux-wrapped
    if grep -E '/usr/local|/home/\$SESSION' $out/bin/.godisc-tmux-wrapped; then exit 1; fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal client for the Discworld MUD";
    longDescription = ''
      godisc is a Go client for the Discworld MUD with telnet transport,
      aliases, highlighting, and chat and experience logs.  Profiles and logs
      live in $GODISC_CONFIG_DIR or ~/.config/godisc.  godisc HOST PORT
      selects a server; godisc-tmux opens a tmux layout and honours
      GODISC_HOST, GODISC_PORT and GODISC_TMUX_SESSION.
    '';
    homepage = "https://github.com/DavidSatimeWallin/godisc";
    license = with lib.licenses; [ mit bsd2 bsd3 ];
    mainProgram = "godisc";
    platforms = [ "x86_64-linux" ];
  };
})
