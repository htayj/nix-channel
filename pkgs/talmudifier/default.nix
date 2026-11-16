{ lib, python3Packages, fetchFromGitHub, fetchurl, texliveBasic, poppler-utils }:

let
  tex = texliveBasic.withPackages (ps: with ps; [
    xetex
    geometry
    marginnote
    sectsty
    ragged2e
    lineno
    xcolor
    paracol
    fontspec
    koma-script
    kvoptions
    kvsetkeys
    ltxcmds
  ]);

  # The upstream font directories omit the redistribution notices of the
  # Culmus Frank-Ruehl and Mekorot Rashi fonts; install them from the
  # font projects' own releases.
  culmusNotices = fetchurl {
    url = "https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2024/tlnet-final/archive/culmus.doc.r68495.tar.xz";
    hash = "sha256-+HXYl6xuR/5ELkKCuLExkaLDuGqkcpTnDjHe2E9yxRI=";
  };
  mekorotNotices = fetchurl {
    url = "mirror://sourceforge/project/mekorot/Mekorot-Fonts/0.03/Mekorot-Fonts-0.03.tar.gz";
    hash = "sha256-UFSoHI7CUeUAKMZcGt6mz0SOv1mPN0wd1nn9nogFHHQ=";
  };
in
python3Packages.buildPythonApplication rec {
  pname = "talmudifier";
  version = "1.1.0-unstable-2020-09-01";
  pyproject = true;

  # Upstream has no release tags; setup.py reports 1.1.0 at this commit.
  src = fetchFromGitHub {
    owner = "subalterngames";
    repo = "talmudifier";
    rev = "1f23206f7b6c899d6ff56bc4ce3fb610ef5cbe56";
    hash = "sha256-hN37gC0tlNni5aeghTGwKb/xZfVWyZhv/py5KgoH3BM=";
  };

  patches = [
    # Report XeLaTeX failures instead of discarding its output.
    ./pdf-writer.patch
    # Find installed recipes, fonts and the engine from any directory, and
    # create Output on writing instead of on import.
    ./api.patch
  ];

  postPatch = ''
    # The tree omits the marker needed by find_packages.
    touch talmudifier/__init__.py

    cp ${./runtime.py} talmudifier/runtime.py
    substituteInPlace talmudifier/runtime.py \
      --replace-fail @DATA@ $out/share/talmudifier \
      --replace-fail @XELATEX@ ${tex}/bin/xelatex

    # PyHyphen downloads its dictionaries; Pyphen ships en_US.  Pyphen
    # iterates longest-first, so keep upstream's ascending split order.
    substituteInPlace setup.py \
      --replace-fail "'pyhyphen'" "'pyphen'"
    substituteInPlace talmudifier/word.py \
      --replace-fail "from hyphen import Hyphenator" "from pyphen import Pyphen" \
      --replace-fail "Hyphenator('en_US')" "Pyphen(lang='en_US', right=3)" \
      --replace-fail "self.H.pairs(self.word)" "reversed(list(self.H.iterate(self.word)))"

    # Current setuptools no longer provides pkg_resources.
    substituteInPlace talmudifier/talmudifier.py \
      --replace-fail "import pkg_resources" "" \
      --replace-fail 'pkg_resources.resource_filename(__name__, "header.txt")' \
                     'str(Path(__file__).with_name("header.txt"))'
  '';

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    pdfminer-six
    pyphen
    tqdm
  ];

  postInstall = ''
    data=$out/share/talmudifier
    doc=$out/share/doc/talmudifier

    # setup.py declares no package data.
    install -Dm644 -t $out/${python3Packages.python.sitePackages}/talmudifier \
      talmudifier/header.txt

    mkdir -p $data
    cp -r fonts $data/fonts
    install -Dm644 -t $data/recipes recipes/default.json
    install -Dm644 -t $data/test test/test_input.md
    install -Dm644 -t $data test_input_reader.py

    install -Dm644 -t $doc README.md LICENSE
    for font in averia garamond; do
      install -Dm644 -t $doc/fonts/$font fonts/$font/OFL.txt
    done
    for font in fell_french_canon fell_flowers; do
      install -Dm644 -t $doc/fonts/$font "fonts/$font/Fell Types License.txt"
    done
    mkdir font-notices
    tar xf ${culmusNotices} -C font-notices
    tar xf ${mekorotNotices} -C font-notices
    install -Dm644 -t $doc/fonts/culmus \
      font-notices/doc/fonts/culmus/{README.md,LICENSE,LICENSE-BITSTREAM,GNU-GPL}
    install -Dm644 -t $doc/fonts/rashi \
      font-notices/Mekorot-Fonts/Rashi/{License,lppl.txt}

    # Upstream has no console entry point, only an example script that
    # expects to run inside the source tree.
    install -Dm755 ${./launcher.py} $out/bin/talmudifier
    substituteInPlace $out/bin/talmudifier \
      --replace-fail @PYTHON@ ${python3Packages.python.interpreter}
  '';

  # Upstream has no test suite.  Typeset the bundled example with the
  # installed command, then caller text through the API, each from an empty
  # directory without XeLaTeX on PATH.
  nativeCheckInputs = [ poppler-utils ];
  checkPhase = ''
    runHook preCheck

    run=$(mktemp -d)
    pushd $run
    env -i PATH=/nonexistent HOME=$run/home LC_ALL=C.UTF-8 \
      $out/bin/talmudifier > ../talmudifier-run.log
    cat ../talmudifier-run.log
    grep -qx TALMUDIFIER_RUNTIME_OK ../talmudifier-run.log
    test "$(echo *)" = Output
    test "$(echo Output/*)" = "Output/test_page.pdf Output/test_page.tex"
    grep -q 'Talmudifier Test Page' Output/test_page.tex
    pdftotext -enc UTF-8 Output/test_page.pdf test_page.txt
    tr -s '[:space:]' ' ' < test_page.txt > test_page.flat
    grep -q 'Talmudifier Test Page' test_page.flat
    popd

    api=$(mktemp -d)
    pushd $api
    env -i PATH=/nonexistent HOME=$api LC_ALL=C.UTF-8 \
      PYTHONPATH=$out/${python3Packages.python.sitePackages}:$PYTHONPATH \
      PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 \
      ${python3Packages.python.interpreter} ${./api-check.py}
    pdftotext -enc UTF-8 Output/api_page.pdf api_page.txt
    tr -s '[:space:]' ' ' < api_page.txt > api_page.flat
    grep -q 'Independent API Document' api_page.flat
    grep -q 'Offline left commentary' api_page.flat
    popd

    test -s $out/share/doc/talmudifier/fonts/culmus/GNU-GPL
    test -s $out/share/doc/talmudifier/fonts/rashi/lppl.txt

    runHook postCheck
  '';

  pythonImportsCheck = [ "talmudifier.talmudifier" ];

  meta = {
    description = "Generate Talmud-style document layouts from local text";
    longDescription = ''
      Talmudifier turns three columns of Markdown-like text into a
      Talmud-style page using bundled fonts and a JSON layout recipe, typeset
      with XeLaTeX.  The talmudifier command typesets the bundled example and
      copies test_page.pdf and test_page.tex into an Output directory below
      the current directory.  The Python API resolves a recipe from the
      caller's recipes directory or an explicit path first and falls back to
      the installed default recipe and fonts.
    '';
    homepage = "https://github.com/subalterngames/talmudifier";
    # Code is MIT.  Bundled fonts: Averia Libre, EB Garamond and the Fell
    # types are OFL; Culmus Frank-Ruehl is GPL-2.0 without an embedding
    # exception, which also covers its subsets in generated PDFs; Mekorot
    # Rashi is LPPL.
    license = with lib.licenses; [ mit ofl gpl2Only lppl13c ];
    mainProgram = "talmudifier";
    platforms = [ "x86_64-linux" ];
  };
}
