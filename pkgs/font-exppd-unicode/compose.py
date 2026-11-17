#!/usr/bin/env python3
"""Compose complete licensed TTF data; do not subset to game text.

The resulting font, including these modifications, is distributed under the
SIL Open Font License 1.1.  Original Droid data retains its Apache 2.0 notices.
"""

import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile

from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem


FAMILY = "ExpPD Unicode Sans"
POSTSCRIPT_NAME = "ExpPDUnicodeSans-Regular"
# 1970-01-01 in the OpenType epoch (1904), independent of the build clock.
FONT_TIMESTAMP = 2082844800
AOSP_COMMIT = "9b19b93a5b0018414784cfdc070b462ea65451d8"
AOSP_URL = (
    "https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/"
    + AOSP_COMMIT + "/data/fonts/"
)
NOTO_COMMIT = "e3bdd5e75581e2b46d93343ec98594f3c89669c0"
NOTO_URL = (
    "https://raw.githubusercontent.com/notofonts/notofonts.github.io/"
    + NOTO_COMMIT + "/fonts/"
)
NOTICE_NAMES = {0: "Copyright", 7: "Trademark", 8: "Manufacturer",
                9: "Designer", 11: "Vendor URL", 12: "Designer URL",
                13: "License", 14: "License URL"}


def notices(font):
    """Retain every distinct upstream attribution, not just an English record."""
    return sorted({(record.nameID, record.toUnicode())
                   for record in font["name"].names
                   if record.nameID in NOTICE_NAMES})


def set_name(font, name_id, text):
    font["name"].removeNames(nameID=name_id)
    # Unicode and Windows records avoid lossy encoding of copyright notices.
    font["name"].setName(text, name_id, 0, 4, 0)
    font["name"].setName(text, name_id, 3, 1, 0x409)


def compose(args):
    with TTFont(args.noto, recalcTimestamp=False) as noto, \
            TTFont(args.droid, recalcTimestamp=False) as droid:
        source_notices = [("Noto Sans Regular", notices(noto)),
                          ("Droid Sans Fallback", notices(droid))]
        codepoints = set(noto.getBestCmap()) | set(droid.getBestCmap())
        if noto["head"].unitsPerEm != 1000:
            raise ValueError("the Noto input must have 1000 units per em")
        if droid["head"].unitsPerEm != 256:
            raise ValueError("the pinned Droid input must have 256 units per em")
        scale_upem(droid, 1000)
        droid["head"].created = droid["head"].modified = FONT_TIMESTAMP
        with tempfile.TemporaryDirectory(prefix="exppd-font-") as temporary:
            scaled = str(Path(temporary) / "DroidSansFallback-scaled.ttf")
            droid.save(scaled, reorderTables=True)
            # The first font supplies the default cmap glyph for overlaps.
            merged = Merger().merge([str(args.noto), scaled])

    try:
        missing = codepoints - set(merged.getBestCmap())
        if missing:
            raise ValueError("font composition lost source Unicode mappings: "
                             + ", ".join(f"U+{cp:04X}" for cp in sorted(missing)))
        # Replace every primary/legacy family identity, including localized
        # records.  Upstream names remain only in attribution, not branding.
        for name_id in (1, 2, 3, 4, 5, 6, 16, 17, 18, 20, 21, 22, 25):
            merged["name"].removeNames(nameID=name_id)
        for name_id, text in {
            1: FAMILY, 2: "Regular", 3: "ExpPDUnicodeSans;1.000;Regular",
            4: FAMILY + " Regular", 5: "Version 1.000", 6: POSTSCRIPT_NAME,
            16: FAMILY, 17: "Regular", 18: FAMILY + " Regular",
            21: FAMILY, 22: "Regular",
        }.items():
            set_name(merged, name_id, text)
        for name_id in (0, 7, 8, 9):
            text = "\n".join(dict.fromkeys(
                value for _, records in source_notices
                for record_id, value in records if record_id == name_id))
            if text:
                set_name(merged, name_id, text)
        set_name(merged, 10,
                 "Modified font: complete Noto Sans and Droid Sans Fallback "
                 "TTF data merged Noto-first; Droid rescaled from 256 to 1000 "
                 "units per em; renamed ExpPD Unicode Sans. Typography differs "
                 "from the game's original font. See accompanying NOTICE.txt.")
        set_name(merged, 13,
                 "This modified Font Software is licensed under the SIL Open "
                 "Font License, Version 1.1. Original Droid font data was "
                 "licensed under Apache License 2.0; its copyright and license "
                 "notices are retained in Apache-2.0-NOTICE.txt. See OFL.txt "
                 "and NOTICE.txt distributed with this font.")
        set_name(merged, 14, "https://openfontlicense.org/open-font-license-official-text/")
        merged.recalcTimestamp = False
        merged["head"].created = merged["head"].modified = FONT_TIMESTAMP
        merged["head"].fontRevision = 1.0
        # Do not identify the independent composite as an upstream vendor build.
        merged["OS/2"].achVendID = "NONE"
        args.output.parent.mkdir(parents=True, exist_ok=True)
        merged.save(args.output, reorderTables=True)
    finally:
        merged.close()

    args.doc_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.noto_license, args.doc_dir / "OFL.txt")
    shutil.copyfile(args.droid_notice, args.doc_dir / "Apache-2.0-NOTICE.txt")
    provenance = [
        FAMILY + " version 1",
        "",
        "This modified font as a whole is distributed under SIL OFL 1.1.",
        "The original Droid data retains its Apache 2.0 license and notices.",
        "No Reserved Font Name is claimed for this composite.",
        "Upstream author and trademark names below are attribution, not endorsement.",
        "",
        "Modifications: merged complete Noto Sans Regular and Droid Sans Fallback",
        "TTF data, Noto-first; scaled Droid from 256 to 1000 units per em; replaced",
        "family and style identities; normalized timestamps and font revision.",
        "No text-derived glyph subset is used. This is composition from upstream",
        "TTF data, not compilation from the original outline-design sources.",
        "It is not a pixel-identical recreation of the game's original font.",
        "",
        "Noto input: Guix font-google-noto " + args.noto_version + " (ttf output)",
        "Noto release commit: " + NOTO_COMMIT,
        "Noto TTF: " + NOTO_URL + "NotoSans/hinted/ttf/NotoSans-Regular.ttf",
        "Noto license: " + NOTO_URL + "LICENSE",
        "Droid TTF: " + AOSP_URL + "DroidSansFallback.ttf",
        "Droid NOTICE: " + AOSP_URL + "NOTICE",
        "",
    ]
    for label, path in (("Noto TTF", args.noto), ("Droid TTF", args.droid),
                        ("OFL.txt", args.noto_license),
                        ("Apache-2.0-NOTICE.txt", args.droid_notice)):
        provenance.append(label + " SHA256: " + hashlib.sha256(path.read_bytes()).hexdigest())
    for label, records in source_notices:
        provenance.extend(["", label + " original name-table notices:"])
        for name_id, text in records:
            provenance.extend([NOTICE_NAMES[name_id] + ":", text])
    (args.doc_dir / "NOTICE.txt").write_text("\n".join(provenance) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("noto", "droid", "output", "noto-license", "droid-notice", "doc-dir"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--noto-version", required=True)
    compose(parser.parse_args())


if __name__ == "__main__":
    main()
