{
  lib,
  sbcl,
  fetchFromGitHub,
  applyPatches,
  libtiff,
}:

sbcl.buildASDFSystem {
  pname = "cl-libtiff";
  version = "0.1";

  # Load libtiff (>= 4.5 API, SONAME 6) by absolute store path, so loading the
  # system does not depend on the dynamic linker cache or LD_LIBRARY_PATH.
  # The substitution is applied to src rather than through a top-level
  # postPatch, which buildASDFSystem would run a second time on the already
  # patched source.
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "shamazmazum";
      repo = "cl-libtiff";
      # Tag v0.1.
      rev = "14587dbb916dc4dad4e68bc66e4b5844b011d693";
      hash = "sha256-dhlGm5L/XyTTZPLwHFgy7To0OOAS7+y0PGACu6GpMZE=";
    };
    postPatch = ''
      substituteInPlace src/libtiff.lisp \
        --replace-fail '"libtiff.so.6"' '"${lib.getLib libtiff}/lib/libtiff.so.6"'
    '';
  };

  # The test system needs cl-value-noise, which nixpkgs does not provide.
  systems = [ "cl-libtiff" ];
  lispLibs = with sbcl.pkgs; [
    cffi
    serapeum
  ];

  meta = {
    description = "Common Lisp wrapper around libtiff";
    longDescription = ''
      cl-libtiff is a CFFI wrapper around libtiff for reading and writing TIFF
      images, including RGBA image reads, tag access, per-scanline I/O and
      directory manipulation.
    '';
    homepage = "https://github.com/shamazmazum/cl-libtiff";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.linux;
  };
}
