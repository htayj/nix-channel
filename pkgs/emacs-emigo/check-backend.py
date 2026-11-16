"""Install check for the Emigo backend.

    check-backend.py BACKEND NOTICES GRAMMAR_LIBRARIES TLS_FIXTURES

Runs without Emacs or network access beyond loopback: path containment, the
approval list, the bundled tokenizer vocabulary, repository map generation,
tag queries, grammar licence notices and certificate-authority selection.
"""

import ast
import json
import os
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import warnings

backend, notices, grammar_libraries, tls = sys.argv[1:5]
sys.path.insert(0, backend)

import repomapper
import tools
from grep_ast import filename_to_lang
from grep_ast.parsers import PARSERS
from grep_ast.tsl import get_language
from session import Session
from tree_sitter import Query

JAVASCRIPT = """\
function gamma(x) {
  return delta(x);
}

class Shape {
  area() {
    return gamma(1);
  }
}
"""

CSHARP = """\
namespace Demo {
  interface IShape : IComparable { double Area(); }
  class Box<T> : Base, IShape where T : Widget, new() {
    Gadget field = new Gadget();
    public double Area() { return field.Measure(); }
  }
}
"""

# Languages with a tag query that the language pack maps a file name to.
QUERIED = {
    "c", "cpp", "csharp", "dart", "elisp", "elixir", "elm", "go", "hcl",
    "java", "javascript", "kotlin", "ocaml", "php", "python", "ruby", "rust",
    "typescript",
}


def expect_value_error(function, *arguments):
    try:
        function(*arguments)
    except ValueError:
        return
    raise SystemExit(f"{function.__name__}{arguments} did not raise ValueError")


with tempfile.TemporaryDirectory() as scratch:
    scratch = os.path.realpath(scratch)
    root = os.path.join(scratch, "project")
    os.mkdir(root)
    outside = os.path.join(scratch, "outside.txt")
    with open(outside, "w") as stream:
        stream.write("outside\n")
    with open(os.path.join(root, "mod.py"), "w") as stream:
        stream.write("def alpha(x):\n    return beta(x) + 1\n\n"
                     "def beta(y):\n    return y * 2\n")
    with open(os.path.join(root, "main.py"), "w") as stream:
        stream.write("from mod import alpha\n\nprint(alpha(1))\n")
    os.symlink(outside, os.path.join(root, "link.txt"))
    os.symlink(scratch, os.path.join(root, "up"))
    escapes = ("../outside.txt", "link.txt", "up/outside.txt", outside)

    # Tool paths stay inside the session root.
    assert tools._resolve_path(root, "mod.py") == os.path.join(root, "mod.py")
    for escape in escapes:
        expect_value_error(tools._resolve_path, root, escape)

    # Creating a session loads cl100k_base from the bundled vocabulary.
    session = Session(root)
    assert session.tokenizer.encode("hello world") == [15339, 1917]

    # Chat context and its file cache stay inside the session root.
    for escape in escapes:
        added, message = session.add_file_to_context(os.path.join(root, escape))
        assert not added and "outside session directory" in message, message
        expect_value_error(session._update_file_cache, escape)

    # Tree-sitter tag queries produce a repository map.
    repository_map = session.repo_mapper.generate_map()
    assert "mod.py" in repository_map and "alpha" in repository_map, repository_map

    # Every installed tag query compiles against its language-pack grammar.
    compiled = set()
    for language in sorted(set(PARSERS.values())):
        query_file = repomapper.get_scm_fname(language)
        if query_file is not None:
            Query(get_language(language), query_file.read_text())
            compiled.add(language)
    assert compiled == QUERIED, compiled ^ QUERIED
    assert filename_to_lang("a.cs") == "csharp"

    # JavaScript and C# tags come from their queries, not the Pygments
    # fallback, which reports references on line -1.
    def tags(name, text):
        path = os.path.join(root, name)
        with open(path, "w") as stream:
            stream.write(text)
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            found = list(session.repo_mapper.repo_mapper.get_tags_raw(path, name))
        assert all(tag.line >= 0 for tag in found), found
        return ({tag.name for tag in found if tag.kind == "def"},
                {tag.name for tag in found if tag.kind == "ref"})

    definitions, references = tags("shapes.js", JAVASCRIPT)
    assert {"gamma", "Shape", "area"} <= definitions, definitions
    assert {"gamma", "delta"} <= references, references
    definitions, references = tags("Shapes.cs", CSHARP)
    assert {"Demo", "IShape", "Box", "Area"} <= definitions, definitions
    assert {"IComparable", "Base", "Widget", "Gadget", "Measure"} <= references, references

# Every grammar library of the language pack has licence evidence installed.
with open(os.path.join(notices, "language_definitions.json")) as stream:
    grammars = json.load(stream)
libraries = {name.removeprefix("libtree_sitter_").removesuffix(".so")
             for name in os.listdir(grammar_libraries)}
assert libraries == {grammar.get("c_symbol", name)
                     for name, grammar in grammars.items()}, libraries
assert set(os.listdir(os.path.join(notices, "grammars"))) == set(grammars)
for name in grammars:
    evidence = [
        os.path.join(directory, file)
        for directory, _, files in os.walk(os.path.join(notices, "grammars", name))
        for file in files
    ]
    assert evidence and all(os.path.getsize(file) for file in evidence), name
for text in ("LICENSE", "README", "licenses/Apache-2.0.txt",
             "licenses/BSD-2-Clause.txt", "licenses/ISC.txt",
             "licenses/LLVM-exception.txt", "licenses/MIT.txt"):
    assert os.path.getsize(os.path.join(notices, text)), text

# Certificate authorities.  A loopback TLS server presents a certificate for
# localhost issued by the private authority trusted.pem; other.pem is an
# unrelated authority.
from litellm.llms.custom_httpx import http_handler

server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_context.load_cert_chain(os.path.join(tls, "server.pem"),
                               os.path.join(tls, "server.key"))
listener = socket.create_server(("127.0.0.1", 0))
port = listener.getsockname()[1]


def serve():
    while True:
        connection, _ = listener.accept()
        try:
            with server_context.wrap_socket(connection, server_side=True) as stream:
                stream.recv(4096)
                stream.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n"
                               b"Connection: close\r\n\r\nok")
        except OSError:
            connection.close()


threading.Thread(target=serve, daemon=True).start()

AUTHORITY_VARIABLES = ("SSL_VERIFY", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE",
                       "SSL_CERT_DIR")


def litellm_context(**environment):
    """The TLS context LiteLLM builds for a provider under ENVIRONMENT."""
    for variable in AUTHORITY_VARIABLES:
        os.environ.pop(variable, None)
    os.environ.update(environment)
    http_handler._ssl_context_cache.clear()
    context = http_handler.get_ssl_configuration()
    assert isinstance(context, ssl.SSLContext), context
    assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname
    return context


def connects(hostname="localhost", **environment):
    """Whether a verified handshake with the loopback server succeeds."""
    context = litellm_context(**environment)
    with socket.create_connection(("127.0.0.1", port), timeout=10) as plain:
        try:
            with context.wrap_socket(plain, server_hostname=hostname):
                return True
        except ssl.SSLCertVerificationError:
            return False


def path(name):
    return os.path.join(tls, name)


# The private authority is trusted only when named, and only for localhost.
assert not connects()
assert connects(SSL_CERT_FILE=path("trusted.pem"))
assert not connects("emigo.invalid", SSL_CERT_FILE=path("trusted.pem"))
assert not connects(SSL_CERT_FILE=path("other.pem"))
assert connects(SSL_VERIFY=path("trusted.pem"))
assert connects(REQUESTS_CA_BUNDLE=path("trusted.pem"))
assert connects(SSL_CERT_DIR=path("trusted"))

# Earlier variables win.
assert not connects(SSL_VERIFY=path("other.pem"), SSL_CERT_FILE=path("trusted.pem"))
assert not connects(SSL_CERT_FILE=path("other.pem"),
                    REQUESTS_CA_BUNDLE=path("trusted.pem"))
assert connects(REQUESTS_CA_BUNDLE=path("trusted.pem"), SSL_CERT_DIR=path("empty"))

# A directory without the authority, or one that does not exist, trusts
# nothing; OpenSSL reads certificate directories during the handshake.
assert not connects(SSL_CERT_DIR=path("empty"))
assert not connects(SSL_CERT_DIR=path("missing"))

# A named file that cannot be loaded is an error, not a reason to trust the
# bundled authorities.
for variable in ("SSL_VERIFY", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"):
    try:
        litellm_context(**{variable: path("missing.pem")})
    except OSError:
        continue
    raise SystemExit(f"missing {variable} file was accepted")

# LiteLLM's own HTTP client completes a request over the same selection.
litellm_context(SSL_CERT_FILE=path("trusted.pem"))
response = http_handler.HTTPHandler().get(f"https://localhost:{port}/")
assert response.status_code == 200 and response.text == "ok", response
litellm_context()
try:
    http_handler.HTTPHandler().get(f"https://localhost:{port}/")
except Exception as error:
    assert "CERTIFICATE_VERIFY_FAILED" in str(error), error
else:
    raise SystemExit("LiteLLM trusted an unknown authority")
for variable in AUTHORITY_VARIABLES:
    os.environ.pop(variable, None)
http_handler._ssl_context_cache.clear()

# Commands, writes and replacements all require approval.
with open(os.path.join(backend, "emigo.py")) as stream:
    tree = ast.parse(stream.read())
approval_lists = [
    {element.id for element in node.value.elts}
    for node in ast.walk(tree)
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "require_approval_list"
            for target in node.targets)
]
assert approval_lists == [
    {"TOOL_EXECUTE_COMMAND", "TOOL_WRITE_TO_FILE", "TOOL_REPLACE_IN_FILE"}
], approval_lists

# The LLM worker starts through sys.executable and needs the same closure.
subprocess.run([sys.executable, "-c", "import epc, litellm, tiktoken"], check=True)
