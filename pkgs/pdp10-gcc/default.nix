{ lib
, gcc14Stdenv
, fetchurl
, bison
, flex
, texinfo
, perl
, m4
, makeWrapper
}:

let
  target = "pdp10-unknown-tops20";
  rev = "3c67a2b56b8a02041bdfca00d012bcccbe4168e5";
  # Bundled notices, installed under their source-relative paths.
  notices = [
    "COPYING" "COPYING.LIB" "gcc/COPYING" "gcc/COPYING.LIB"
    "boehm-gc/doc/README" "libffi/LICENSE" "zlib/zlib.h" "libjava/LIBGCJ_LICENSE"
  ];
  noDefaultAssembler = "/* This compiler has no default target assembler. */";
in
gcc14Stdenv.mkDerivation (finalAttrs: {
  pname = "pdp10-gcc";
  # Version identified by gcc/version.c at the pinned revision.
  version = "3.2-20020416";

  src = fetchurl {
    url = "https://codeload.github.com/larsbrinkhoff/pdp10-gcc/tar.gz/${rev}";
    name = "pdp10-gcc-${rev}.tar.gz";
    hash = "sha256-DN2UR80l/5fjaoIDmZn+4cLuZfal174dyd11d6VMiNI=";
  };

  nativeBuildInputs = [ bison flex texinfo perl m4 makeWrapper ];

  # GCC 3.2 predates the hardening flags.
  hardeningDisable = [ "all" ];

  postPatch = ''
    # GCC 3.2 increments a cast result, which current C rejects.
    substituteInPlace include/obstack.h --replace-fail \
      '*((void **)__o->next_free)++ = ((void *)datum);' \
      '(*((void **) __o->next_free) = ((void *) datum), __o->next_free += sizeof (void *));'

    # genmultilib writes nested scripts with literal /bin/sh shebangs.
    sed -i 's|^#!/bin/sh|#!${gcc14Stdenv.shell}|' gcc/genmultilib
    if grep -q '^#!/bin/sh' gcc/genmultilib; then
      echo 'genmultilib shebangs unchanged' >&2
      exit 1
    fi
    test "$(grep -c '^#!${gcc14Stdenv.shell}' gcc/genmultilib)" = 4

    # --with-as=macro selects the TOPS-20 MACRO dialect but also defines a
    # relative default assembler that gcc.c would try before PATH.
    sed -i 's|^#define DEFAULT_ASSEMBLER.*|${noDefaultAssembler}|' gcc/configure
    if grep -q '^#define DEFAULT_ASSEMBLER' gcc/configure; then
      echo 'DEFAULT_ASSEMBLER definition unchanged' >&2
      exit 1
    fi
    grep -qxF '${noDefaultAssembler}' gcc/configure
  '';

  # GCC needs a separate build directory; configure probes use K&R C.
  configurePhase = ''
    runHook preConfigure
    export CFLAGS=-std=gnu89
    export CONFIG_SHELL=${gcc14Stdenv.shell}
    mkdir build
    cd build
    ../configure --prefix=$out \
      --build=x86_64-linux \
      --host=x86_64-linux \
      --target=${target} \
      --enable-languages=c \
      --disable-nls \
      --disable-multilib \
      --disable-shared \
      --disable-threads \
      --disable-libgcj \
      --disable-checking \
      --with-as=macro
    runHook postConfigure
  '';

  # The cross `all' goal also builds libgcc, which needs a target assembler.
  # start.encap is the driver and cc1 subset needed for -S. The old top-level
  # makefile clears MAKEOVERRIDES, so the override is passed through --eval.
  buildPhase = ''
    runHook preBuild
    make all-gcc '--eval=override ALL=start.encap'
    runHook postBuild
  '';

  enableParallelBuilding = false;
  # No PDP-10 assembler, linker or runtime exists to test against.
  doCheck = false;

  installPhase = ''
    runHook preInstall
    libdir=$out/lib/gcc-lib/${target}/3.2
    install -d $out/bin
    cp -p gcc/xgcc $out/bin/${target}-gcc
    cp -p gcc/cpp $out/bin/${target}-cpp
    install -Dm755 gcc/cc1 $libdir/cc1
    install -Dm644 gcc/specs $libdir/specs
    # Keep the plain `as' and `ld' lookups away from host tools.
    wrapProgram $out/bin/${target}-gcc \
      --set PATH $out/bin \
      --set GCC_EXEC_PREFIX $out/lib/gcc-lib/
    doc=$out/share/doc/pdp10-gcc-${finalAttrs.version}
    for f in ${lib.escapeShellArgs notices}; do
      install -Dm644 "../$f" "$doc/$f"
    done
    runHook postInstall
  '';

  meta = {
    description = "GCC 3.2 C compiler that emits PDP-10 TOPS-20 MACRO assembly";
    longDescription = ''
      The PDP-10 backend of GCC 3.2 for the pdp10-unknown-tops20 target.
      pdp10-unknown-tops20-gcc and pdp10-unknown-tops20-cpp preprocess C and
      emit MACRO assembly with -S. No PDP-10 assembler, linker, C library or
      runtime is included, so assembling and linking are unsupported.
    '';
    homepage = "https://github.com/larsbrinkhoff/pdp10-gcc";
    # Compiler GPL-2.0+, libiberty LGPL-2.0+/2.1+, plus the bundled libffi,
    # zlib and Boehm GC notices.
    license = with lib.licenses; [ gpl2Plus lgpl2Plus lgpl21Plus mit zlib boehmGC ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "pdp10-unknown-tops20-gcc";
  };
})
