"""Typeset caller text through the installed API from an empty directory."""
from pathlib import Path

from talmudifier.style import Style
from talmudifier.talmudifier import Talmudifier
from talmudifier.word import Word

word = Word("Morbi", Style(False, False, False), None, None)
assert not word.pairs, "en_US must not leave a two-character suffix"

left = "Offline left commentary discusses local documents and thoughtful interpretation. " * 6
center = "Independent central passage examines typesetting without a network connection. " * 3
right = "Right commentary compares typography and meaningful local source material. " * 6

# No recipes or fonts directory and no XeLaTeX on PATH: the installed recipe,
# fonts and engine must be found by the package itself.
talmudifier = Talmudifier(left, center, right)
document = talmudifier.writer.write(
    talmudifier.get_chapter("Independent API Document") + "\n" + talmudifier.get_tex(),
    "api_page")
Path("Output/api_page.tex").write_text(document, encoding="utf-8")
