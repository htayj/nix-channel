{ lib, emacsPackages, fetchFromGitHub, fetchurl, makeWrapper, openssl, python3
, writeText }:

# Differences from the Guix recipe (guix/tay/packages/emigo.scm), all from
# the pinned Nixpkgs Python set:
#
# - LiteLLM 1.106.2 instead of 1.78.0.  Its top-level enterprise directory
#   is already absent.  The certificate-authority edits below are re-derived
#   for this version; Guix additionally falls back to its store trust
#   bundle, where this package falls back to the certifi bundle in the
#   closure.
# - grep-ast 0.9.0 with tree-sitter 0.25.2 and tree-sitter-language-pack
#   1.4.1, whose 248 grammars are upstream's prebuilt parser bundle; Guix
#   builds tree-sitter-languages 0.5.0 from source.  The prebuilt bundle
#   ships no licence texts, so they are installed here from the pinned
#   grammar revisions.
# - The language pack names C# csharp and has no mapping for .ql files,
#   so ql-tags.scm is unused.
# - The launcher clears PYTHONPATH.
let
  python = python3.override {
    self = python;
    packageOverrides = final: previous: {
      # Emigo passes LiteLLM no TLS settings, so the environment is the only
      # way to name a certificate authority.  Upstream ignores
      # REQUESTS_CA_BUNDLE and SSL_CERT_DIR and silently substitutes the
      # certifi bundle for an SSL_VERIFY or SSL_CERT_FILE path that does not
      # exist.  Authorities are now taken from the first of an SSL_VERIFY
      # path, SSL_CERT_FILE, REQUESTS_CA_BUNDLE, SSL_CERT_DIR and certifi; a
      # named file that cannot be loaded is an error.  Verification and
      # hostname checking stay as upstream has them.  Chat completions use
      # this Python path; LiteLLM's optional Rust transport is not involved.
      litellm = previous.litellm.overridePythonAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace litellm/llms/custom_httpx/http_handler.py \
            --replace-fail 'if isinstance(ssl_verify, str) and os.path.exists(ssl_verify):' \
              'if isinstance(ssl_verify, str):' \
            --replace-fail 'ssl_cert_file: Final = os.getenv("SSL_CERT_FILE")' \
              'ssl_cert_file: Final = os.getenv("SSL_CERT_FILE") or os.getenv("REQUESTS_CA_BUNDLE")' \
            --replace-fail 'if ssl_cert_file and os.path.exists(ssl_cert_file):' \
              'if ssl_cert_file:' \
            --replace-fail 'cafile = certifi.where()' \
              'cafile = None if os.getenv("SSL_CERT_DIR") else certifi.where()' \
            --replace-fail 'ssl.create_default_context(cafile=cafile)' \
              'ssl.create_default_context(cafile=cafile, capath=os.getenv("SSL_CERT_DIR") if cafile is None else None)'
        '';
        # Importing LiteLLM builds a TLS context, and the build sandbox
        # exports SSL_CERT_FILE=/no-cert-file.crt.
        postFixup = (old.postFixup or "") + ''
          unset SSL_CERT_FILE
        '';
      });
    };
  };

  # requirements.txt, plus sexpdata, which utils.py imports directly.
  pythonEnv = python.withPackages (ps: with ps; [
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

  languagePack = python.pkgs.tree-sitter-language-pack;

  # Licence evidence for every grammar of the prebuilt parser bundle, at the
  # revisions in the language pack's sources/language_definitions.json.
  # Regenerate with update-grammar-notices.sh when the language pack changes.
  grammarNoticeFiles = lib.concatMap (grammar: map (file: {
    destination = "grammars/${grammar.name}/${file.path}";
    source = fetchurl {
      name = "${grammar.name}-${baseNameOf file.path}";
      url = "https://raw.githubusercontent.com/${lib.removePrefix "https://github.com/" grammar.repo}/${file.rev}/${file.path}";
      inherit (file) sha256;
    };
  }) grammar.files) (lib.importJSON ./grammar-notices.json);

  # Standard texts for the grammars that name their licence without
  # including it.
  spdxText = name: sha256: fetchurl {
    url = "https://raw.githubusercontent.com/spdx/license-list-data/v3.27.0/text/${name}.txt";
    inherit sha256;
  };
  spdxTexts = lib.mapAttrs spdxText {
    "Apache-2.0" = "074e6e32c86a4c0ef8b3ed25b721ca23aca83df277cd88106ef7177c354615ff";
    "BSD-2-Clause" = "f32fb3b417a194167cfad068223fc975ba96c5960513a10f66a3c28720aec1df";
    "ISC" = "f2ec607f67bb0dd3053b49835b02110d5cd0f8eb6da3aac4dc0b142a6b299be9";
    "LLVM-exception" = "e34c58338bd89d43e709e226610d8f32b3e3c47f4ad9a99a8dc1d4ac7842488e";
    "MIT" = "b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5";
  };

  grammarNoticesReadme = writeText "emigo-grammar-notices" ''
    Emigo's repository map loads the prebuilt tree-sitter grammars of
    tree-sitter-language-pack ${languagePack.version}.  LICENSE is the
    language pack's own licence and language_definitions.json lists the
    repository and revision each grammar was built from.

    grammars/NAME holds, from that revision of the grammar's repository:

    - its licence, copying and notice files;
    - where the repository has none, the package manifests in which its
      author declares the licence: MIT for corn, eds, eex, elsa, facility,
      move, tmux and vb, BSD-2-Clause for pgn, and MIT in Cargo.toml and
      pyproject.toml but ISC in package.json for brightscript and
      cooklang.  The standard texts of those licences are in licenses/;
    - hand-written parser sources that carry their own copyright notice
      (d, erlang, perl, pkl, postscript, powershell, qmljs).

    Two licence files come from another revision of the same repository.
    The groovy grammar is pinned to a deployment commit holding only
    generated sources; its LICENSE is that of the source commit the
    deployment was generated from.  The tmux repository added its LICENSE
    after the pinned revision.

    The wast and wat grammars are under Apache-2.0 WITH LLVM-exception and
    ship only that identifier; both texts are in licenses/.
  '';

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
  nativeInstallCheckInputs = [ openssl ];

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

    # tree-sitter 0.25 executes queries through QueryCursor.  Upstream keeps
    # queries for the language pack's grammars in their own directory but
    # never reads it; prefer it, as Aider does.
    substituteInPlace repomapper.py \
      --replace-fail 'from grep_ast import TreeContext, filename_to_lang' \
        $'from grep_ast import TreeContext, filename_to_lang\nfrom tree_sitter import Query, QueryCursor' \
      --replace-fail 'query = language.query(query_scm)' \
        'query = Query(language, query_scm)' \
      --replace-fail 'captures = query.captures(tree.root_node)' \
        'captures = QueryCursor(query).captures(tree.root_node)' \
      --replace-fail 'query_path = script_dir / "queries" / "tree-sitter-languages" / f"{lang}-tags.scm"' \
        $'query_path = script_dir / "queries" / "tree-sitter-language-pack" / f"{lang}-tags.scm"\n        if not query_path.is_file():\n            query_path = script_dir / "queries" / "tree-sitter-languages" / f"{lang}-tags.scm"'

    # The C# query targets an older grammar under the name c_sharp.
    cp queries/tree-sitter-languages/c_sharp-tags.scm \
      queries/tree-sitter-language-pack/csharp-tags.scm
    substituteInPlace queries/tree-sitter-language-pack/csharp-tags.scm \
      --replace-fail 'bases: (base_list' '(base_list' \
      --replace-fail 'target: (identifier)' '(identifier)' \
      --replace-fail '(type_constraint' '(type_parameter_constraint'

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
    notices=$out/share/doc/emacs-emigo/third-party/tree-sitter-language-pack
    install -Dm644 ${grammarNoticesReadme} $notices/README
    install -Dm644 ${languagePack.src}/LICENSE \
      ${languagePack.src}/sources/language_definitions.json -t $notices
    ${lib.concatStrings (lib.mapAttrsToList (name: text: ''
      install -Dm644 ${text} $notices/licenses/${name}.txt
    '') spdxTexts)}
    ${lib.concatMapStrings (file: ''
      install -Dm644 ${file.source} "$notices/${file.destination}"
    '') grammarNoticeFiles}
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/emigo-python \
      --unset PYTHONPATH \
      --set TIKTOKEN_CACHE_DIR $out/share/emigo/tiktoken \
      --set LITELLM_LOCAL_MODEL_COST_MAP True
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR PYTHONDONTWRITEBYTECODE=1
    # The sandbox names a certificate file that does not exist.
    unset SSL_CERT_FILE
    (
      cd $out/share/emigo/backend
      $out/bin/emigo-python test_setup.py
      $out/bin/emigo-python repomapper.py --help > /dev/null
    )

    # Two private authorities and a localhost certificate from the first.
    tls=$TMPDIR/tls
    mkdir -p $tls/trusted $tls/empty
    for authority in trusted other; do
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -days 2 -subj "/CN=Emigo check $authority authority" \
        -addext basicConstraints=critical,CA:TRUE \
        -addext keyUsage=critical,keyCertSign \
        -keyout $tls/$authority.key -out $tls/$authority.pem 2> /dev/null
    done
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -subj "/CN=localhost" -keyout $tls/server.key -out $tls/server.csr \
      2> /dev/null
    printf '%s\n' subjectAltName=DNS:localhost basicConstraints=CA:FALSE \
      keyUsage=critical,digitalSignature extendedKeyUsage=serverAuth \
      subjectKeyIdentifier=hash authorityKeyIdentifier=keyid > $tls/server.ext
    openssl x509 -req -in $tls/server.csr -CA $tls/trusted.pem \
      -CAkey $tls/trusted.key -CAcreateserial -days 2 \
      -extfile $tls/server.ext -out $tls/server.pem 2> /dev/null
    cp $tls/trusted.pem \
      $tls/trusted/$(openssl x509 -hash -noout -in $tls/trusted.pem).0

    $out/bin/emigo-python ${./check-backend.py} $out/share/emigo/backend \
      $out/share/doc/emacs-emigo/third-party/tree-sitter-language-pack \
      ${languagePack}/share/tree-sitter-language-pack/libs $tls
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

      Provider connections verify certificates against the first of an
      SSL_VERIFY path, SSL_CERT_FILE, REQUESTS_CA_BUNDLE, SSL_CERT_DIR and
      the bundled certifi authorities; a named file that cannot be loaded
      is an error.  Licence texts for the prebuilt tree-sitter grammars are
      in share/doc/emacs-emigo/third-party.
    '';
    homepage = "https://github.com/MatthewZMD/emigo";
    # Apache-2.0 for Emigo, GPL-3.0-or-later for emigo-epc.el, and MIT for
    # the tokenizer vocabulary.  The grammar notices in share/doc belong to
    # the tree-sitter-language-pack dependency.
    license = with lib.licenses; [ asl20 gpl3Plus mit ];
    platforms = [ "x86_64-linux" ];
  };
}
