{ lib, stdenv, fetchFromGitHub }:

let
  # Upstream transcripts compared after check.sh, which itself always exits 0.
  expectedTranscripts = [
    "@.its.dasm" "@.midas.dasm" "arc.code.list" "atsign.tcp.dasm"
    "boot.exb.dasm" "cerber.sav.dasm" "chars.pub.oct.sail"
    "chars.pub.sail.ascii" "dart.dmp.dasm" "dart.tape.dart" "dired.dmp.dasm"
    "eftp.sav.dasm" "its.bin.dasm" "its.rp06.dasm" "l.bin.dump"
    "linum-1.txt-a" "linum-1.txt-df" "linum-2.txt-af" "linum-2.txt-df"
    "linum-3.txt-d" "logo.ptp.dump" "macro.low.dasm" "nswit.bin.dump"
    "pt.rim.dasm" "pt.rim.dump" "srccom.exe.dasm" "stink.-ipak-.ipak"
    "supdup.bin.dump" "system.dmp.dasm" "system.dmp.dump" "ts.ksfedr.dasm"
    "ts.name.dasm" "ts.obs.dasm" "ts.srccom.dasm" "ts.srccom.dump"
    "two.tapes.dasm" "visib1.bin.dasm" "visib2.bin.dasm" "visib3.bin.dasm"
  ];
  scrambleModes = [ "thirty" "sixbit" "pdpten" "aaaaaa" "0s" ];
  programs = [
    "dis10" "acct" "calcomp" "cat36" "classify-tape" "constantinople"
    "cross" "dart" "decdmp" "dskdmp" "dump" "dumper" "failsafe"
    "harscntopbm" "ipak" "itsarc" "kldcp" "klfedr" "linum" "macdmp"
    "macro-tapes" "magdmp" "magfrm" "mini-dumper" "od10" "old-cpio" "palx"
    "plt" "scrmbl" "tape-dir" "tendmp" "tito" "tvpic" "unscr"
  ];
in
stdenv.mkDerivation {
  pname = "pdp10-its-disassembler";
  # Upstream has no releases.
  version = "0-unstable-c745bb5";

  # tvpic builds the lodepng submodule.
  src = fetchFromGitHub {
    owner = "larsbrinkhoff";
    repo = "pdp10-its-disassembler";
    rev = "c745bb51e6b38f89b2d0ce95edb45833dbdd937d";
    fetchSubmodules = true;
    hash = "sha256-mDdHKd4UT4TpCjQ+EjgOV/KV3Cy+oiKOapDOWfUmnzk=";
  };

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "AR=${stdenv.cc.targetPrefix}ar"
  ];

  # The all target runs check.sh, which executes dis10, as a peer of dis10.
  enableParallelBuilding = false;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sh check.sh
    for expected in ${lib.escapeShellArgs expectedTranscripts}; do
      cmp "out/$expected" "test/$expected"
    done
    # Upstream scrmbl round trips print failures without failing.
    for mode in ${lib.escapeShellArgs scrambleModes}; do
      ./scrmbl -Wbin "$mode" samples/zeros.scrmbl "out/$mode.scrmbl"
      ./cat36 -Wits -Xbin "out/$mode.scrmbl" | cmp - "samples/zeros.$mode.scrmbl"
      ./scrmbl -d -Wits "$mode" "out/$mode.scrmbl" "out/$mode.unscrm"
      ./cat36 -Wits -Xbin "out/$mode.unscrm" | cmp - samples/zeros.scrmbl
    done
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ${lib.escapeShellArgs programs}
    install -Dm644 -t $out/share/doc/pdp10-its-disassembler \
      README README.md COPYING tito.doc
    install -Dm644 lodepng/LICENSE \
      $out/share/doc/pdp10-its-disassembler/LODEPNG-LICENSE
    runHook postInstall
  '';

  meta = {
    description = "Disassemble and manipulate PDP-10 ITS files";
    longDescription = ''
      PDP10 ITS Disassembler provides dis10 together with utilities for
      inspecting, extracting, converting, and manipulating PDP-10 ITS tapes,
      dumps, archives, and word-format files.
    '';
    homepage = "https://github.com/larsbrinkhoff/pdp10-its-disassembler";
    # tvpic includes lodepng (zlib).
    license = with lib.licenses; [ gpl2Only zlib ];
    platforms = lib.platforms.unix;
    mainProgram = "dis10";
  };
}
