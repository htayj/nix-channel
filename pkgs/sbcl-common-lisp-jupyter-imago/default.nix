{
  lib,
  sbcl,
  fetchFromGitHub,
}:

# The stock jupyter-lab-extension ASDF component copies the prebuilt JupyterLab
# extension into XDG_DATA_HOME whenever the system is compiled, which happens
# again on load when the copied files look newer than the store FASLs. This
# variant models the extension as static files and installs it as package data
# under share/jupyter/labextensions, where Jupyter finds it through
# XDG_DATA_DIRS.
#
# The Quicklisp 2025-06-22 release calls SB-IMPL::MAKE-EVAL-LAMBDA, which SBCL
# 2.6.8 no longer has; upstream defines its own MAKE-EVAL-LAMBDA since
# e769131b, so the source is taken from there.
sbcl.pkgs.common-lisp-jupyter.overrideLispAttrs (old: {
  pname = "common-lisp-jupyter-imago";
  version = "0-unstable-2026-11-22";
  src = fetchFromGitHub {
    owner = "yitzchak";
    repo = "common-lisp-jupyter";
    rev = "e769131be17a7f304685fe1a58f8d85e94605475";
    sha256 = "0gn0hf6rxr2mws0gab3zyclqpbipx3nhxm04iyzxhd172g556wnp";
  };
  patches = [ ./sbcl-common-lisp-jupyter-imago-static-extension.patch ];
  lispLibs = lib.filter (dep: dep.pname != "jupyter-lab-extension") old.lispLibs;

  postInstall = ''
    mkdir -p $out/share/jupyter/labextensions
    cp -r debugger-restarts/prebuilt \
      $out/share/jupyter/labextensions/debugger-restarts-clj
  '';

  meta = (old.meta or { }) // {
    description = "Common Lisp Jupyter kernel with its lab extension installed as package data";
    homepage = "https://github.com/yitzchak/common-lisp-jupyter";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
