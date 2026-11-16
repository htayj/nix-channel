{ lib, python3Packages, fetchFromGitHub }:

python3Packages.buildPythonApplication rec {
  pname = "dorxng-mcp";
  version = "0.1.0";
  pyproject = true;

  # Upstream has no tags; pin the commit that declares 0.1.0.
  src = fetchFromGitHub {
    owner = "htayj";
    repo = "dorxng-mcp";
    rev = "59b810609f5bccadf6c9eedc8d6b1ded1dc6cea1";
    hash = "sha256-DzjHNqVMFxV6p3ABPSDTSPWAghRH8r0raDC2pNquuIQ=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [
    # The server imports mcp.server.fastmcp, which MCP SDK 2 renamed to
    # mcp.server.mcpserver.  Package sets from before the split have only
    # the 1.x SDK, under the plain name.
    (python3Packages.mcp_1 or python3Packages.mcp)
    python3Packages.requests
    python3Packages.urllib3
  ];

  nativeCheckInputs = [ python3Packages.unittestCheckHook ];
  unittestFlags = [ "-s" "tests" ];

  pythonImportsCheck = [ "dorxng_mcp.server" ];

  postInstall = ''
    install -Dm644 -t $out/share/doc/dorxng-mcp README.md
  '';

  # The MCP client starts the server with a minimal environment, so this
  # also shows that the installed launcher finds its own dependencies.
  postInstallCheck = ''
    ${python3Packages.python.interpreter} ${./check-session.py} $out/bin/dorxng-mcp
  '';

  meta = {
    description = "MCP server for private DorXNG and SearXNG searches";
    longDescription = ''
      DorXNG MCP is a Model Context Protocol server, spoken over stdio, for
      authorized searches against private DorXNG or SearXNG instances.  Its
      tools run read-only searches, store de-duplicated results in a
      DorXNG-compatible SQLite database on request, regex-search such a
      database, and return search-operator guidance.  The default endpoint
      is https://127.0.0.1:8443/search; pass another server or a
      newline-delimited server list per call.
    '';
    homepage = "https://github.com/htayj/dorxng-mcp";
    # Declared in pyproject.toml; the repository has no licence file.
    license = lib.licenses.mit;
    mainProgram = "dorxng-mcp";
    platforms = [ "x86_64-linux" ];
  };
}
