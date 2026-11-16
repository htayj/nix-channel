#!@PYTHON@
"""Render the installed local example without writing to immutable assets."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from talmudifier.runtime import DATA, tex_environment


def main():
    if len(sys.argv) != 1:
        raise SystemExit("usage: talmudifier (writes Output/test_page.pdf and .tex)")
    destination = Path.cwd() / "Output"
    with tempfile.TemporaryDirectory(prefix="talmudifier-") as temporary:
        work = Path(temporary)
        for name in ("recipes", "fonts", "test"):
            (work / name).symlink_to(DATA / name, target_is_directory=True)
        shutil.copyfile(DATA / "test_input_reader.py", work / "test_input_reader.py")
        (work / "Output").mkdir()
        # Share the same installed engine/data/TeX environment as the API.
        with tex_environment() as (_, environment):
            environment.update({
                # The Nix wrapper extends sys.path in this process only.
                "PYTHONPATH": os.pathsep.join(path for path in sys.path if path),
                "PYTHONNOUSERSITE": "1",
                "PYTHONDONTWRITEBYTECODE": "1",
            })
            returncode = subprocess.run(
                [sys.executable, str(work / "test_input_reader.py")],
                cwd=work, env=environment).returncode
        try:
            if returncode:
                raise subprocess.CalledProcessError(returncode, "test_input_reader.py")
        except subprocess.CalledProcessError:
            # Retain only diagnostics created by this invocation.  The checked
            # writer also emits their contents before the workspace is removed.
            diagnostics = Path(tempfile.mkdtemp(
                prefix="talmudifier-diagnostics-", dir=destination.parent))
            for log in (work / "Output").glob("*.log"):
                shutil.copyfile(log, diagnostics / log.name)
            print(f"XeLaTeX diagnostics: {diagnostics}", file=sys.stderr)
            raise
        pdf = work / "Output/test_page.pdf"
        tex = work / "Output/test_page.tex"
        if not pdf.is_file() or not tex.is_file():
            raise RuntimeError("XeLaTeX did not produce both output files")
        destination.mkdir(exist_ok=True)
        for output in (pdf, tex):
            shutil.copyfile(output, destination / output.name)
    print("TALMUDIFIER_RUNTIME_OK")


if __name__ == "__main__":
    main()
