{
  lib,
  sbcl,
  fetchFromGitHub,
  applyPatches,
  libheif,
}:

sbcl.buildASDFSystem {
  pname = "cl-libheif";
  version = "1.1.0";

  # Load libheif (SONAME 1) by absolute store path, so loading the system does
  # not depend on the dynamic linker cache or LD_LIBRARY_PATH. The substitution
  # is applied to src rather than through a top-level postPatch, which
  # buildASDFSystem would run a second time on the already patched source.
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "shamazmazum";
      repo = "cl-libheif";
      # Tag v1.1.0.
      rev = "3f74c17b7313eeb179eefe87ffd00bcf54a53751";
      hash = "sha256-tbDn9pn5GWaTn7a2qJsOAjisZKCnGOixtpVXyvDEaN8=";
    };
    postPatch = ''
      substituteInPlace src/library.lisp \
        --replace-fail '"libheif.so.1"' '"${lib.getLib libheif}/lib/libheif.so.1"'
    '';
  };

  # The ASDF build compiles src/tiny-wrapper.c with cc against <libheif/heif.h>
  # into src/tiny-wrapper.so, which is installed with the sources.
  nativeLibs = [ libheif ];

  # The test system needs cl-value-noise, which nixpkgs does not provide.
  systems = [ "cl-libheif" ];
  lispLibs = with sbcl.pkgs; [
    cffi
    cffi-libffi
    serapeum
    split-sequence
    trivial-octet-streams
  ];

  meta = {
    description = "Common Lisp wrapper around libheif";
    longDescription = ''
      cl-libheif is a CFFI wrapper around libheif for decoding and encoding
      HEIF images and reading their metadata. On x86-64 a small C shim is
      compiled at build time so libheif can write through a Lisp callback.
    '';
    homepage = "https://github.com/shamazmazum/cl-libheif";
    license = lib.licenses.bsd2;
    platforms = [ "x86_64-linux" ];
  };
}
