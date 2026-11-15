{
  lib,
  buildGoModule,
  fetchFromGitHub,
  runtimeShell,
  socat,
  util-linux,
}:

buildGoModule (finalAttrs: {
  pname = "go-mud";
  version = "0.6.6";

  # The lua directory is a gitlink to the vanished dzpao/lua-mud-robots
  # repository; it stays empty and submodules are not fetched.
  src = fetchFromGitHub {
    owner = "mudclient";
    repo = "go-mud";
    rev = "4116008fef3cc961e9e251af89ecf2769015351c";
    hash = "sha256-o3rdGlIVbSB4CGb1GfpWgU/nwZ/Z9pN6FirwGjij+gk=";
  };

  vendorHash = "sha256-D8tvm9Yo56JGTLLeLzS7J84mOyt7JYaBCN3MtakwJ9Y=";

  # Upstream's go:generate step records the checkout, host name, clock and
  # local Go version.  Write the same variables with fixed values.
  postPatch = ''
    cat > app/version.go <<'EOF'
    package app

    var Contributors = []struct {
    	Name  string
    	Lines int
    }{}

    var (
    	AppName        = "GoMud"
    	Version        = "v${finalAttrs.version}"
    	BuildTime      = "1970-01-01 00:00:00 UTC"
    	BuildGoVersion = "Nix"
    	BuildHost      = "reproducible"
    )
    EOF
  '';

  subPackages = [ "." ];

  ldflags = [ "-s" "-w" ];

  postInstall = ''
    doc=$out/share/doc/go-mud
    install -Dm644 LICENSE README.md config-example.json config-example.yaml -t $doc
    # Preserve the notices of every vendored module.
    (cd vendor && find . -type f \( -name 'LICENSE*' -o -name 'license*' \
        -o -name 'COPYING*' -o -name 'NOTICE*' -o -name PATENTS \) \
      -exec install -Dm644 {} $doc/modules/{} \;)
  '';

  # Offline session on a pseudo-terminal against a loopback server: the
  # greeting is drawn, a Lua robot loaded with -p answers it, a typed command
  # reaches the server and quit ends the client.  Nothing is written to HOME.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ socat util-linux ];
  installCheckPhase = ''
    runHook preInstallCheck
    # The version report goes to standard error.
    $out/bin/go-mud --version 2>&1 | grep -F 'v${finalAttrs.version}'
    $out/bin/go-mud --help | grep -F -- '--mud.host'

    export HOME=$TMPDIR/home TERM=xterm
    mkdir -p $HOME $TMPDIR/play/robot
    cd $TMPDIR/play
    printf '%s\n' 'printf "Welcome to go-mud-smoke\r\n"' \
      'while read -r line; do printf "%s\n" "$line" >> received; done' > greet.sh
    printf '%s\n' 'Print("lua-smoke-loaded")' \
      'function OnReceive(raw, line)' \
      '  if string.find(line, "go%-mud%-smoke") then Send("hello-from-lua") end' \
      'end' \
      'function OnSend(cmd) return true end' > robot/main.lua

    socat TCP-LISTEN:42421,bind=127.0.0.1,reuseaddr \
      EXEC:"${runtimeShell} greet.sh" &
    server=$!
    sleep 1
    # The client exits before the slack input is used up, so that input may
    # hit a closed pipe; only the client's exit status matters.
    { { sleep 5; printf 'look\r'; sleep 3; printf 'quit\r'; sleep 3; } 2>/dev/null || true; } \
      | timeout 60 script -q -e -c \
          "stty rows 24 cols 80; exec $out/bin/go-mud -H 127.0.0.1 -P 42421 -p robot" \
          typescript
    kill $server 2>/dev/null || true
    tr -d '\000' < typescript > screen
    grep -aqF 'Welcome to go-mud-smoke' screen
    grep -aqF 'lua-smoke-loaded' screen
    grep -aqF 'hello-from-lua' received
    grep -aqF 'look' received
    test -z "$(ls -A $HOME)"
    runHook postInstallCheck
  '';

  meta = {
    description = "UTF-8 terminal client for text-based MUD servers";
    longDescription = ''
      GoMud is a terminal MUD client oriented toward Chinese-language games.
      It handles Telnet negotiation and several Chinese character encodings
      and runs Lua robots.  config.yaml or config.json is read from the
      working directory or given with -c, and -p selects the directory
      holding main.lua.  No robot scripts are shipped.
    '';
    homepage = "https://github.com/mudclient/go-mud";
    license = with lib.licenses; [ gpl3Only asl20 bsd2 bsd3 mit mpl20 ];
    mainProgram = "go-mud";
    platforms = [ "x86_64-linux" ];
  };
})
