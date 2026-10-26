{ lib, stdenv, fetchFromGitHub, nasm, runtimeShell, coreutils, qemu_kvm }:

stdenv.mkDerivation {
  pname = "bootrogue";
  version = "0-unstable-118e1cb";

  # Upstream publishes no tags; this is its only branch head.
  src = fetchFromGitHub {
    owner = "nanochess";
    repo = "bootRogue";
    rev = "118e1cb7818fdd152b4f008548408ed0ed45e06f";
    hash = "sha256-Nydj9gCkv5Tu3GQ6RdwoIDKb8xZF3UPudkkItNY694A=";
  };

  nativeBuildInputs = [ nasm ];

  dontConfigure = true;

  # The COM build only proves the source assembles in both modes; the boot
  # sector image is the installed runtime asset.
  buildPhase = ''
    runHook preBuild
    nasm -f bin rogue.asm -l rogue.lst -o rogue.img
    nasm -f bin rogue.asm -Dcom_file=1 -o rogue.com
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 rogue.img $out/share/bootrogue/rogue.img
    install -Dm444 -t $out/share/doc/bootrogue LICENSE README

    mkdir -p $out/bin
    substitute ${./bootrogue.sh} $out/bin/bootrogue \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by coreutils ${coreutils} \
      --subst-var-by qemu ${qemu_kvm} \
      --subst-var-by image $out/share/bootrogue/rogue.img
    chmod 555 $out/bin/bootrogue
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$(stat -c %s $out/share/bootrogue/rogue.img)" -eq 512
    test "$(od -An -tx1 -j 510 -N 2 $out/share/bootrogue/rogue.img | tr -d ' ')" = 55aa
    status=0
    $out/bin/bootrogue --bad 2>/dev/null || status=$?
    test "$status" -eq 64
    runHook postInstallCheck
  '';

  meta = {
    description = "Roguelike game that fits in a boot sector";
    longDescription = ''
      BootRogue is a 510-byte 8086 real-mode roguelike.  This package
      assembles the boot image from source and runs it in QEMU as a read-only,
      snapshot-backed floppy with no network.  `bootrogue --smoke` sends a few
      arrow keys through the QEMU monitor and checks for a nonblank VGA
      screendump.
    '';
    homepage = "https://github.com/nanochess/bootRogue";
    license = lib.licenses.bsd2;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bootrogue";
  };
}
