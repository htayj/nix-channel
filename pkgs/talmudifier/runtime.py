"""Installed data and isolated XeLaTeX state for Talmudifier's Python API."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import tempfile

DATA = Path("@DATA@")
XELATEX = "@XELATEX@"


def recipe_path(name):
    """Prefer caller recipes and explicit files, then the installed recipes."""
    requested = Path(name)
    for candidate in (Path("recipes") / requested, requested):
        if candidate.is_file():
            return candidate.resolve()
    # Only recipe names, not missing explicit paths, select installed recipes.
    if requested.name == str(requested):
        installed = DATA / "recipes" / requested
        if installed.is_file():
            return installed
    raise FileNotFoundError(f"Couldn't find recipe: {name}")


def load_recipe(name):
    """Read a recipe, relocating only the installed recipe's bundled fonts."""
    path = recipe_path(name)
    with path.open(encoding="utf-8") as stream:
        recipe = json.load(stream)
    if path.parent.resolve() != (DATA / "recipes").resolve():
        return recipe

    def font_path(value):
        if value.startswith("fonts/"):
            return str(DATA / value) + ("/" if value.endswith("/") else "")
        return value

    for font in recipe.get("fonts", {}).values():
        if "path" in font:
            font["path"] = font_path(font["path"])
        citation = font.get("citation", {})
        if "path" in citation:
            citation["path"] = font_path(citation["path"])
    recipe["misc_definitions"] = [
        re.sub(r"(\bPath\s*=\s*)(fonts/[^,\]\s}]+)",
               lambda match: match[1] + font_path(match[2]), definition)
        for definition in recipe.get("misc_definitions", [])
    ]
    return recipe


@contextmanager
def tex_environment():
    """Yield the configured engine and child-only, disposable TeX environment."""
    with tempfile.TemporaryDirectory(prefix="talmudifier-tex-") as temporary:
        work = Path(temporary)
        environment = os.environ.copy()
        for variable, name in (
            ("HOME", "home"),
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_DATA_HOME", "data"),
            ("XDG_CACHE_HOME", "cache"),
            ("XDG_STATE_HOME", "state"),
            ("XDG_RUNTIME_DIR", "run"),
            ("TMPDIR", "tmp"),
            ("TMP", "tmp"),
            ("TEMP", "tmp"),
            ("TEXMFHOME", "texmf-home"),
            ("TEXMFVAR", "texmf-var"),
            ("TEXMFCONFIG", "texmf-config"),
            ("TEXMFCACHE", "texmf-cache"),
        ):
            directory = work / name
            directory.mkdir(mode=0o700, exist_ok=True)
            environment[variable] = str(directory)
        # XeTeX starts its PDF driver by name; the TeX environment's own
        # texmf.cnf already locates the store trees and prebuilt formats.
        search = [str(Path(XELATEX).parent)]
        if environment.get("PATH"):
            search.append(environment["PATH"])
        environment.update({
            "PATH": os.pathsep.join(search),
            "MKTEXPK": "0",
            "MKTEXTFM": "0",
        })
        yield XELATEX, environment
