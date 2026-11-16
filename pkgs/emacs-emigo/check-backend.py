"""Install check for the Emigo backend.

Runs without Emacs or network access: path containment, the approval list,
the bundled tokenizer vocabulary, and repository map generation.
"""

import ast
import os
import subprocess
import sys
import tempfile

backend = sys.argv[1]
sys.path.insert(0, backend)

import tools
from session import Session


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
