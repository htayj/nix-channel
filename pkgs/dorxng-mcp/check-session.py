"""Drive an installed dorxng-mcp server through one MCP stdio session.

Usage: check-session.py /path/to/bin/dorxng-mcp

Only the tools that need no SearXNG instance are called.
"""

import asyncio
import json
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

EXPECTED_TOOLS = {
    "dorxng_search",
    "dorxng_search_and_store",
    "dorxng_query_database",
    "dorxng_get_dorking_guidance",
    "dorxng_get_setup_info",
}


async def call(session, tool, arguments):
    """Call TOOL and return the payload the server wrapped in its reply."""
    result = await session.call_tool(tool, arguments)
    assert not result.isError, (tool, result.content)
    return json.loads(result.content[0].text)


async def check(server):
    parameters = StdioServerParameters(command=server)
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            initialized = await session.initialize()
            assert initialized.serverInfo.name == "dorxng-mcp", initialized.serverInfo

            tools = {tool.name for tool in (await session.list_tools()).tools}
            assert tools == EXPECTED_TOOLS, tools

            setup = await call(session, "dorxng_get_setup_info", {})
            assert setup["ok"] and setup["default_server"].endswith("/search"), setup

            guidance = await call(
                session,
                "dorxng_get_dorking_guidance",
                {"target": "example.com", "objective": "files", "file_types": ["pdf"]},
            )
            queries = [template["query"] for template in guidance["templates"]]
            assert guidance["ok"], guidance
            assert any("site:example.com" in query for query in queries), queries
            assert any("filetype:pdf" in query for query in queries), queries

            # Optional arguments left out exercise the server's None defaults.
            broad = await call(session, "dorxng_get_dorking_guidance", {})
            assert broad["ok"] and broad["objective"] == "broad", broad

            missing = await call(
                session, "dorxng_query_database", {"database": "/nonexistent/dorxng.db"}
            )
            assert not missing["ok"], missing
            assert missing["error"]["type"] == "FileNotFoundError", missing


asyncio.run(asyncio.wait_for(check(sys.argv[1]), timeout=120))
print("dorxng-mcp stdio session: 5 tools listed, 4 calls answered")
