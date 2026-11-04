{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "uc-explorer";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "uc-explorer";
    rev = "fc4f9f3324d3497f553512b661ad37cbdde89ccb";
    hash = "sha256-7BHZvAyKJ9r2XK18U/7hZwXxTplg7RNGm/0QQeiV6Pw=";
  };

  # Byte-identical copy of upstream's Cargo.lock at the pinned revision.  The
  # cargo setup hook diffs it against the source lockfile, and every crate is
  # fetched against the checksums in its [metadata] table.  Like the Guix
  # package, build and test with --locked so the reviewed graph is used as is.
  #
  # Guix deletes the prebuilt MinGW import libraries (lib/*.a) shipped by the
  # winapi-{i686,x86_64}-pc-windows-gnu crates.  Their build scripts only use
  # them for Windows GNU targets, so a Linux build never links them; here they
  # stay in the checksum-verified vendor tree and are not part of the output.
  cargoLock.lockFile = ./Cargo.lock;

  cargoBuildFlags = [ "--locked" ];
  cargoTestFlags = [ "--locked" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    uc=$out/bin/uc-explorer

    $uc --version | grep -Fx 'Symbolics Microcode Explorer 1.0'

    if $uc 2>usage.txt; then
      echo 'missing INPUT accepted' >&2; exit 1
    fi
    grep -F 'INPUT' usage.txt

    if $uc missing.mic 2>missing.txt; then
      echo 'missing file accepted' >&2; exit 1
    fi
    grep -F "Couldn't open input file missing.mic" missing.txt

    # Minimal microcode image: header, version 0x1234, comment "NIX", empty A
    # and B memory, one C memory word at address 0, empty type map, EOF.
    printf '\x01\x05\x02\x34\x12\x03\x03NIX\x04\x00\x00\x05\x00\x00' > tiny.mic
    printf '\x06\x01\x00\x00\x00' >> tiny.mic
    printf '\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> tiny.mic
    printf '\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x08' >> tiny.mic
    $uc tiny.mic > tiny.txt
    grep -Fx 'valid ucode' tiny.txt
    grep -Fx 'version=0x1234' tiny.txt
    grep -Fx "comment='NIX'" tiny.txt
    grep -Fx 'a-mem length=0' tiny.txt
    grep -Fx 'b-mem length=0' tiny.txt
    grep -Fx 'c-mem length=1' tiny.txt
    grep -Fx 'type-map length=0' tiny.txt
    grep -Fx 'pico-store length=0' tiny.txt
    grep -Fx '00000>' tiny.txt

    # A truncated image is reported as unparsable.
    head -c 5 tiny.mic > truncated.mic
    $uc truncated.mic | grep -F 'Unable to parse microcode'

    runHook postInstallCheck
  '';

  postInstall = ''
    install -Dm644 README.md docs/microinstruction.bits.txt -t $out/share/doc/uc-explorer
  '';

  meta = {
    description = "Symbolics 3600 microcode file explorer";
    homepage = "https://github.com/larsbrinkhoff/uc-explorer";
    license = lib.licenses.gpl3Plus;
    mainProgram = "uc-explorer";
    platforms = [ "x86_64-linux" ];
  };
})
