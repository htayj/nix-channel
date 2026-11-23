{
  lib,
  sbcl,
  fetchFromGitHub,
  applyPatches,
  sbcl-cl-libheif,
  sbcl-cl-libtiff,
  sbcl-common-lisp-jupyter-imago,
}:

sbcl.buildASDFSystem {
  pname = "imago";
  version = "0.11.0-unstable-2025-02-02";

  # Patches and asset removal are applied to src rather than through a
  # top-level postPatch, which buildASDFSystem would run a second time on the
  # already patched source.
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "tokenrove";
      repo = "imago";
      rev = "b1f50c1192f78dacbaaf60923d341f7c2ee38e92";
      hash = "sha256-c8DWxnRG9EZIq73G+H9YgtwGLl7D5KDcG9Shr0F7H9w=";
    };
    # Keep backends registered by imago/jpeg-turbo, imago/libheif and
    # imago/libtiff when the core system is loaded again, and port the
    # imago/jupyter display method from the removed imago-pngio package to
    # imago:write-png-to-stream.
    patches = [
      ./sbcl-imago-preserve-format-registry.patch
      ./sbcl-imago-jupyter-png-api.patch
    ];
    # The docs/ and tests/ images carry no license grant; only the
    # LLGPL-covered Lisp sources are installed.
    postPatch = ''
      rm -r docs
      find tests -type f ! -name '*.lisp' -delete
    '';
  };

  # imago/tests needs the removed fixtures.
  systems = [
    "imago"
    "imago/bit-io"
    "imago/jpeg-turbo"
    "imago/libheif"
    "imago/libtiff"
    "imago/jupyter"
  ];
  lispLibs =
    (with sbcl.pkgs; [
      alexandria
      cl-base64
      array-operations
      cl-jpeg
      flexi-streams
      float-features
      jpeg-turbo
      pngload
      serapeum
      trivial-gray-streams
      zlib
      zpng
    ])
    ++ [
      sbcl-cl-libheif
      sbcl-cl-libtiff
      sbcl-common-lisp-jupyter-imago
    ];

  meta = {
    description = "Image manipulation library for Common Lisp";
    longDescription = ''
      Imago reads, writes, converts and processes images in Common Lisp, with
      support for PNG, JPEG (classic and libjpeg-turbo), HEIF/HEIC, TIFF, PNM
      and TGA formats, colour space conversions, convolution, morphology,
      resizing and rotation. This package builds the imago, imago/bit-io,
      imago/jpeg-turbo, imago/libheif, imago/libtiff and imago/jupyter
      systems.
    '';
    homepage = "https://github.com/tokenrove/imago";
    # LLGPL: the LGPL 2.1 with Franz's Lisp preamble; nixpkgs has no entry.
    license = {
      fullName = "Lisp Lesser General Public License";
      url = "http://opensource.franz.com/preamble.html";
      free = true;
      redistributable = true;
    };
    platforms = [ "x86_64-linux" ];
  };
}
