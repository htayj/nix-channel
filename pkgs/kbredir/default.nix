{ lib, stdenv, fetchFromGitHub, libx11, libxi, libxtst, xorgproto }:

stdenv.mkDerivation {
  pname = "kbredir";
  # Upstream has no release tag; configure.in declares 0.9 at its sole commit.
  version = "0.9";

  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "kbredir";
    rev = "9b82cf66a60842a97a5b6ffac219e59bcd9f069a";
    hash = "sha256-0DwQJu1pPAeVrb8hCTafdqSlQq4Hay78HTFjGV7/NH8=";
  };

  # This Autotools-era library path does not exist on Nix.  Configure
  # regenerates src/Makefile from Makefile.in; patch both for coherence.
  postPatch = ''
    substituteInPlace src/Makefile.in src/Makefile \
      --replace-fail '-L/usr/X11R6/lib ' ""
  '';

  # XTest.h includes XInput.h, so libxi headers are needed for detection.
  buildInputs = [ libx11 libxi libxtst xorgproto ];

  # The 2000-era source relies on GNU C89 implicit declarations.
  env.NIX_CFLAGS_COMPILE = "-std=gnu89";

  # The upstream check target only rebuilds the tools; exercising a reader
  # would require changing a real console tty.
  doCheck = false;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for p in read_vt220 read_linux_console read_xev \
             write_vt220 write_xsendevent write_xtest; do
      test -x $out/bin/$p
    done
    runHook postInstallCheck
  '';

  postInstall = ''
    install -Dm644 -t $out/share/doc/kbredir COPYING README
  '';

  meta = {
    description = "Redirect keyboard events between terminal and X11 protocols";
    longDescription = ''
      Kbredir provides small command-line tools that translate a line-based
      `<key> down`/`<key> up` protocol between VT220 input or output, Linux
      console raw-keyboard input, xev output, and X11 XSendEvent or XTEST
      output.  read_linux_console switches its controlling console tty to
      K_MEDIUMRAW; use it only on the intended terminal.
    '';
    homepage = "https://github.com/larsbrinkhoff/kbredir";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
