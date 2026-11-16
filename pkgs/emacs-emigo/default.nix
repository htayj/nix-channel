{ lib, emacsPackages, fetchFromGitHub, fetchurl, makeWrapper, python3 }:

let
  # requirements.txt, plus sexpdata, which utils.py imports directly.
  pythonEnv = python3.withPackages (ps: with ps; [
    diskcache
    epc
    gitignore-parser
    grep-ast
    litellm
    networkx
    orjson
    pygments
    scipy
    sexpdata
    tiktoken
    tqdm
  ]);

  # Session creation needs this BPE vocabulary even when no LLM is requested.
  # Tiktoken otherwise downloads it lazily into the user's cache.
  cl100kRanks = fetchurl {
    url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken";
    hash = "sha256-Ijkht27pm96ZW3/3OFE+7xAPtR0YyTWXoRO8/+hlsqc=";
  };

  tokenizerLicense = fetchurl {
    url = "https://raw.githubusercontent.com/openai/tiktoken/0.9.0/LICENSE";
    hash = "sha256-QYy0mbQ2Eo1lPXmUEzOlQ3t74uqSE9zC8E0V1dLFHYY=";
  };
in
emacsPackages.trivialBuild {
  pname = "emigo";
  # Upstream declares 0.5 in emigo.el but has no release tag.
  version = "0.5-unstable-2025-10-13";

  src = fetchFromGitHub {
    owner = "MatthewZMD";
    repo = "emigo";
    rev = "91d122a85cac1965e1a52185ed8711c5ef8f24c9";
    hash = "sha256-wEOlqTNXBViMCTbBkS8jhyyBmD5JmqqqbIi7lrGmt6o=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Declared in the Package-Requires header of emigo.el.
  packageRequires = with emacsPackages; [ compat markdown-mode transient ];

  postPatch = ''
    # Resolve symlinks and reject paths outside the session root before any
    # tool or context access.
    substituteInPlace tools.py \
      --replace-fail 'return os.path.abspath(os.path.join(session_path, rel_path))' \
        $'root = os.path.realpath(session_path)\n    candidate = os.path.realpath(os.path.join(root, rel_path))\n    if os.path.commonpath((root, candidate)) != root:\n        raise ValueError(f"Path escapes session root: {rel_path}")\n    return candidate' \
      --replace-fail 'abs_path = os.path.abspath(os.path.join(session.session_path, rel_path))' \
        'abs_path = _resolve_path(session.session_path, rel_path)'
    substituteInPlace session.py \
      --replace-fail 'abs_path = os.path.abspath(os.path.join(self.session_path, rel_filename))' \
        $'root = os.path.realpath(self.session_path)\n            abs_path = os.path.realpath(os.path.join(root, rel_filename))\n            if os.path.commonpath((root, abs_path)) != root:\n                return False, f"File is outside session directory: {rel_filename}"' \
      --replace-fail 'if not abs_path.startswith(os.path.abspath(self.session_path)):' \
        'if os.path.commonpath((os.path.realpath(self.session_path), abs_path)) != os.path.realpath(self.session_path):' \
      --replace-fail 'abs_path = os.path.abspath(os.path.join(self.session_path, rel_path))' \
        $'root = os.path.realpath(self.session_path)\n        abs_path = os.path.realpath(os.path.join(root, rel_path))\n        if os.path.commonpath((root, abs_path)) != root:\n            raise ValueError(f"Path escapes session root: {rel_path}")'

    # tree-sitter 0.25 executes queries through QueryCursor.
    substituteInPlace repomapper.py \
      --replace-fail 'from grep_ast import TreeContext, filename_to_lang' \
        $'from grep_ast import TreeContext, filename_to_lang\nfrom tree_sitter import Query, QueryCursor' \
      --replace-fail 'query = language.query(query_scm)' \
        'query = Query(language, query_scm)' \
      --replace-fail 'captures = query.captures(tree.root_node)' \
        'captures = QueryCursor(query).captures(tree.root_node)'

    # Replacements modify files, so they need the same explicit approval as
    # commands and writes.
    substituteInPlace emigo.py \
      --replace-fail 'TOOL_EXECUTE_COMMAND, TOOL_WRITE_TO_FILE,' \
        'TOOL_EXECUTE_COMMAND, TOOL_WRITE_TO_FILE, TOOL_REPLACE_IN_FILE,' \
      --replace-fail $'TOOL_WRITE_TO_FILE,\n            # Add other tools' \
        $'TOOL_WRITE_TO_FILE,\n            TOOL_REPLACE_IN_FILE,\n            # Add other tools'

    # Use the installed backend and launcher instead of PATH and the
    # directory of emigo.el.  llm_worker inherits this Python interpreter.
    substituteInPlace emigo.el \
      --replace-fail $'(provide \'emigo)' \
        $'(setq emigo-python-file "${placeholder "out"}/share/emigo/backend/emigo.py")\n(setq emigo-python-command "${placeholder "out"}/bin/emigo-python")\n\n(provide \'emigo)'
  '';

  postInstall = ''
    backend=$out/share/emigo/backend
    install -Dm644 *.py -t $backend
    # RepoMapper resolves its query files beside repomapper.py.
    cp -r queries $backend/queries
    # Tiktoken names a cached vocabulary after the SHA-1 of its URL.
    install -Dm644 ${cl100kRanks} \
      $out/share/emigo/tiktoken/9b5ad71b2ce5302211f9c61530b329a4922fc6a4
    install -Dm644 README.md LICENSE emigo-epc.el -t $out/share/doc/emacs-emigo
    install -Dm644 ${tokenizerLicense} $out/share/doc/emacs-emigo/TOKENIZER-LICENSE
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/emigo-python \
      --unset PYTHONPATH \
      --set TIKTOKEN_CACHE_DIR $out/share/emigo/tiktoken \
      --set LITELLM_LOCAL_MODEL_COST_MAP True
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR PYTHONDONTWRITEBYTECODE=1
    (
      cd $out/share/emigo/backend
      $out/bin/emigo-python test_setup.py
      $out/bin/emigo-python repomapper.py --help > /dev/null
    )
    $out/bin/emigo-python ${./check-backend.py} $out/share/emigo/backend
    ${emacsPackages.emacs}/bin/emacs --batch -Q \
      -L $out/share/emacs/site-lisp --eval "(progn
      (require 'emigo)
      (unless (and (commandp 'emigo)
                   (equal emigo-python-command \"$out/bin/emigo-python\")
                   (file-executable-p emigo-python-command)
                   (equal emigo-python-file
                          \"$out/share/emigo/backend/emigo.py\")
                   (file-readable-p emigo-python-file))
        (error \"Emigo launcher paths unavailable\")))"
    runHook postInstallCheck
  '';

  meta = {
    description = "Emacs client for a local LLM coding-agent backend";
    longDescription = ''
      The installed Python launcher includes the backend's dependency closure
      and the fixed cl100k_base tokenizer vocabulary, so local context
      operations need no downloads.  Provider interactions require a
      separately configured model, endpoint and credentials.  Tool writes,
      replacements and commands require explicit approval.
    '';
    homepage = "https://github.com/MatthewZMD/emigo";
    # Apache-2.0 for Emigo, GPL-3.0-or-later for emigo-epc.el, and MIT for
    # the tokenizer vocabulary.
    license = with lib.licenses; [ asl20 gpl3Plus mit ];
    platforms = [ "x86_64-linux" ];
  };
}
