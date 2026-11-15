"""Serve the installed site through its launcher and fetch it over loopback."""

import os
import re
import subprocess
import sys
import urllib.request

launcher, site = sys.argv[1:]

# Port 0 asks for a free port; the banner names the one chosen.
server = subprocess.Popen(
    [launcher, "0"],
    stdout=subprocess.PIPE,
    text=True,
    env={**os.environ, "PYTHONUNBUFFERED": "1"},
)
try:
    banner = server.stdout.readline()
    port = re.search(r"Serving HTTP on 127\.0\.0\.1 port (\d+)", banner)
    assert port, f"unexpected banner: {banner!r}"

    def fetch(path):
        url = f"http://127.0.0.1:{port.group(1)}{path}"
        with urllib.request.urlopen(url, timeout=30) as response:
            assert response.status == 200, (path, response.status)
            return response.read()

    index = fetch("/").decode()
    assert '<div id="root">' in index, index

    assets = re.findall(r'(?:src|href)="(/assets/[^"]+)"', index)
    scripts = [asset for asset in assets if asset.endswith(".js")]
    styles = [asset for asset in assets if asset.endswith(".css")]
    assert scripts and styles, assets

    for asset in assets:
        with open(site + asset, "rb") as installed:
            assert fetch(asset) == installed.read(), asset

    # The catalog data is compiled into the bundle.
    assert any(b"Radeon" in fetch(script) for script in scripts), scripts
finally:
    server.terminate()
    server.wait()

print(f"served {1 + len(assets)} files on 127.0.0.1:{port.group(1)}")
