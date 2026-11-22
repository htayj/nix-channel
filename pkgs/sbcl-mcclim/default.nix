{
  lib,
  sbcl,
  fetchzip,
}:

sbcl.buildASDFSystem {
  pname = "mcclim";
  version = "1.0.0";

  src = fetchzip {
    # Tag 1.0.0-koliada, commit 2577ea3569bb96e2c46ccc8abed4ce6c327e8ed6.
    url = "https://codeberg.org/McCLIM/McCLIM/archive/1.0.0-koliada.tar.gz";
    hash = "sha256-38WkT6yKAZhlYHFLcJKMnrdwpgylWllCcc6qN2MQA+Y=";
  };

  # buildASDFSystem removes the .asd files of unlisted systems, so every McCLIM
  # system in the closure of mcclim and mcclim-layouts is listed here.
  systems = [
    "mcclim"
    "mcclim-layouts"
    "automaton"
    "clim"
    "clim-core"
    "clim-lisp"
    "clim-pdf"
    "clim-postscript"
    "clim-postscript-font"
    "conditional-commands"
    "drei-mcclim"
    "esa-mcclim"
    "mcclim-bezier"
    "mcclim-bitmaps"
    "mcclim-clx"
    "mcclim-clx-fb"
    "mcclim-fonts"
    "mcclim-franz"
    "mcclim-null"
    "mcclim-render"
    "persistent"
  ];
  lispLibs = with sbcl.pkgs; [
    alexandria
    babel
    bordeaux-threads
    cffi
    cl-aa
    cl-dejavu
    cl-paths-ttf
    cl-pdf
    cl-pdf-parser
    cl-unicode
    cl-vectors
    closer-mop
    cluffer
    cluffer-base
    cluffer-simple-buffer
    cluffer-simple-line
    cluffer-standard-buffer
    cluffer-standard-line
    clump
    clx
    flexi-streams
    flexichain
    global-vars
    opticl
    spatial-trees
    swank
    trivial-features
    trivial-garbage
    trivial-gray-streams
    zpb-ttf
  ];

  meta = {
    description = "Common Lisp Interface Manager II implementation";
    longDescription = ''
      McCLIM is a free implementation of the Common Lisp Interface Manager
      (CLIM II) specification, with a CLX backend, PDF and PostScript output,
      the Drei editor substrate and McCLIM extensions such as layouts and
      accept-values panes.  This is release 1.0.0, newer than the Quicklisp
      snapshot in nixpkgs.
    '';
    homepage = "https://mcclim.common-lisp.dev";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
