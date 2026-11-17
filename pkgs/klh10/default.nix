{
  lib,
  stdenv,
  fetchFromGitHub,
}:

let
  # LICENSE clause 2 asks modified versions to carry an identifier of origin
  # after the version number, in the source and in what the user sees at run
  # time.
  originTag = "nix";

  # The network device processes need libpcap, tun/tap or VDE and elevated
  # privileges; the emulators are built without those devices.
  deviceFlags = lib.concatStringsSep " " [
    "-DKLH10_DEV_NI20=0"
    "-DKLH10_DEV_DPNI20=0"
    "-DKLH10_DEV_CH11=0"
    "-DKLH10_DEV_LHDH=0"
    "-DKLH10_DEV_DPIMP=0"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "klh10";
  # configure.ac says 2.0l; upstream has no release tags.
  version = "2.0l-unstable-2026-08-03";

  src = fetchFromGitHub {
    owner = "PDP-10";
    repo = "klh10";
    rev = "6d733f2a47644964492fd864454cbe1331655e53";
    # README and READaux place run/ and contrib/ (the "Auxiliary
    # Distribution": DEC bootstrap and diagnostic binaries that need a Digital
    # hobbyist licence, ITS system binaries, third-party utilities) outside
    # the KLH10 licence.  Nothing from them is fetched into the store.  The
    # contributed install guide and the CI workflow are not needed either.
    postFetch = ''
      rm -r $out/run $out/contrib $out/READaux $out/install-guides $out/.github
    '';
    hash = "sha256-Te0cTh0APTJfTaJToxTUdG4xOjQKPNYcfqKiP/GpUOo=";
  };

  # tapedd kept the zero that its option parser returns for success as its
  # result, so a completed copy exited 1; its copy loop also read an unset
  # error variable when nothing was skipped.
  #
  # The -help and -version switches were declared but not handled.  They now
  # print and exit before any terminal or machine setup, with one or two
  # dashes.
  #
  # The version banner no longer embeds the compile date and time.
  patches = [ ./klh10-fixes.patch ];

  # The emulators start their disk and tape device processes with execl on a
  # bare file name, which only works from the directory holding them.
  postPatch = ''
    substituteInPlace configure.ac --replace-fail '[2.0l]' '[2.0l-${originTag}]'
    substituteInPlace configure --replace-fail '2.0l' '2.0l-${originTag}'
    substituteInPlace src/klh10.h --replace-fail 'V2.0i' 'V2.0i-${originTag}'
    substituteInPlace src/dvrpxx.c \
      --replace-fail '"dprpxx";' '"${placeholder "out"}/libexec/klh10/dprpxx";'
    substituteInPlace src/dvtm03.c \
      --replace-fail '"dptm03";' '"${placeholder "out"}/libexec/klh10/dptm03";'
  '';

  # configure refuses to run inside the source tree.  The copy taken here,
  # before stdenv rewrites configure's interpreter line, is the modified
  # source installed below.
  preConfigure = ''
    cp -R . ../modified-source
    mkdir ../build
    cd ../build
  '';
  configureScript = "../${finalAttrs.src.name}/configure";

  configureFlags = [
    "--disable-lights"
    "--without-vde"
    "--disable-bridge"
  ];

  # Pre-C99 declarations and tentative definitions shared between objects.
  env.NIX_CFLAGS_COMPILE = "-std=gnu99 -fcommon";

  enableParallelBuilding = true;

  # The top-level Makefile loops over the three build directories in a shell
  # loop that discards failures and builds the network programs as well.
  buildPhase = ''
    runHook preBuild
    for model in kl ks ks-its; do
      make -C bld-$model -j$NIX_BUILD_CORES "CONFFLAGS_USR=${deviceFlags}" \
        kn10-$model dprpxx dptm03
    done
    make -C bld-kl -j$NIX_BUILD_CORES "CONFFLAGS_USR=${deviceFlags}" \
      wfconv tapedd vdkfmt wxtest udlconv uexbconv
    runHook postBuild
  '';

  # Upstream has no check target; wxtest is its self-test of the 36-bit word
  # arithmetic and returns the number of failures.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bld-kl/wxtest -q
    runHook postCheck
  '';

  # Upstream's install target copies into one directory and has no notion of
  # documentation.
  installPhase = ''
    runHook preInstall
    for model in kl ks ks-its; do
      install -Dm755 -t $out/bin bld-$model/kn10-$model
    done
    install -Dm755 -t $out/bin \
      bld-kl/{wfconv,tapedd,vdkfmt,wxtest,udlconv,uexbconv}
    install -Dm755 -t $out/libexec/klh10 bld-kl/{dprpxx,dptm03}
    ln -s kn10-kl $out/bin/klh10

    source=../modified-source
    install -Dm644 -t $out/share/doc/klh10 \
      $source/LICENSE $source/README \
      $source/doc/{cmdref,cmdsum,coding}.txt
    # LICENSE clause 1: modified versions are distributed with their source
    # code and documentation.
    mkdir -p $out/share/klh10
    cp -R $source $out/share/klh10/source
    runHook postInstall
  '';

  # The installed source copy keeps its portable interpreter lines.
  dontPatchShebangs = true;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for program in klh10 kn10-kl kn10-ks kn10-ks-its; do
      $out/bin/$program -version > version.out
      grep -F 'KLH10 2.0l-${originTag}' version.out
      $out/bin/$program --help > help.out
      grep -F 'Usage: klh10' help.out
    done

    # One four-byte record and two tape marks in SIMH TPS form, copied to a
    # second TPS image: a completed copy exits 0 and carries the record.
    printf '\004\000\000\000ABCD\004\000\000\000\000\000\000\000\000\000\000\000' > in.tps
    $out/bin/tapedd itvs=in.tps otvs=out.tps
    od -A d -t x1 out.tps
    grep -q ABCD out.tps
    runHook postInstallCheck
  '';

  meta = {
    description = "KL10 and KS10 PDP-10 host emulator";
    longDescription = ''
      KLH10 emulates the PDP-10 KL10 and KS10 processors and provides an
      interactive front-end console with memory deposit and examine, single
      stepping, breakpoints and device control.  The package has three
      emulators (kn10-kl, also installed as klh10, kn10-ks and kn10-ks-its),
      the disk and tape device processes they start, and the image conversion
      utilities wfconv, tapedd, vdkfmt, udlconv and uexbconv.

      Guest operating systems, boot images and the rest of upstream's
      separately licensed Auxiliary Distribution are not included, and the
      emulators are built without network devices.  The console and command
      references are in share/doc/klh10; the modified source the binaries
      were built from is in share/klh10/source.
    '';
    homepage = "https://github.com/PDP-10/klh10";
    # Derived from the University of Washington Free-Fork License: use,
    # modification and redistribution with source are permitted; modified
    # versions carry an origin tag and keep the notices; modifications that
    # depend on unreleasable proprietary material may not be distributed.
    # Installed as share/doc/klh10/LICENSE.
    license = {
      shortName = "klh10-free-fork";
      fullName = "KLH10 Free-Fork License";
      url = "https://github.com/PDP-10/klh10/blob/${finalAttrs.src.rev}/LICENSE";
      free = true;
      redistributable = true;
    };
    platforms = [ "x86_64-linux" ];
    mainProgram = "klh10";
  };
})
