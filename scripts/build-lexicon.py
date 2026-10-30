#!/usr/bin/env python3
"""Builds Throughline's word-study lexicon (Workstream D).

Two independent outputs, both derived from verified public-domain sources:

1. **KJV Strong's tag side channel** (`Resources/Lexicon/kjv-tags/<BOOK>.json`) —
   extracted directly from `scripture-source/kjv/*.usfm`, the same raw USFM the
   app's own `USFMParser` reads. This script does NOT use or modify
   `USFMParser.swift`; it re-parses the USFM independently (chapter/verse
   tracking mirrors that parser's line-based approach) so the two can never
   fight over the same file, per the workstream's file-ownership rule.

2. **Strong's Hebrew/Greek dictionaries** (`Resources/Lexicon/strongs-greek.json`,
   `strongs-hebrew.json`) — built from the raw 1890/1894 Strong's e-text XML
   hosted at github.com/openscriptures/strongs. That repository ALSO publishes
   a pre-converted JSON/JS version of each dictionary marked
   "Copyright 2009/2010, Open Scriptures. CC-BY-SA" — this script deliberately
   does NOT use that JSON. It parses the raw XML instead, which carries its own
   explicit "Public Domain -- Copy Freely" (Greek prologue) / `<rights>Public
   Domain</rights>` (Hebrew OSIS header) declaration, and independently
   recombines the original PD text fields (lemma, transliteration,
   pronunciation, derivation, definition, KJV usage) into this app's own
   JSON shape. The Hebrew source file also embeds pointers into Strong's
   *Theological Wordbook of the Old Testament* (TWOT, copyright 1980 Moody
   Publishers) via a `gloss="4a"`-style attribute on each entry; this script
   never reads that attribute or any TWOT content.

Usage:
    python3 scripts/build-lexicon.py --out-dir /private/tmp/st-lexicon-stage \
        [--usfm-dir scripture-source/kjv] [--cache-dir /private/tmp/st-lexicon-cache] \
        [--no-network]

Output is written to --out-dir (a staging directory outside the package) —
the caller is responsible for verifying it and moving it into
`Sources/StudyTable/Resources/Lexicon/` atomically, per the project's
"generated data is swapped in atomically" rule. Deterministic: two runs over
the same inputs produce byte-identical JSON (stable key order via ordered
dict insertion, not lexicographic sort, so "10:1" doesn't collide with "2:1";
`sort_keys=False`, fixed `separators`, `ensure_ascii=False`).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

GREEK_XML_URL = "https://raw.githubusercontent.com/openscriptures/strongs/master/greek/StrongsGreekDictionaryXML_1.4/strongsgreek.xml"
HEBREW_XML_URL = "https://raw.githubusercontent.com/openscriptures/strongs/master/hebrew/StrongHebrewG.xml"
OSIS_NS = "{http://www.bibletechnologies.net/2003/OSIS/namespace}"

# ---------------------------------------------------------------------------
# USFM Strong's-tag extraction (independent of USFMParser.swift)
# ---------------------------------------------------------------------------

# Canonical KJV filenames use a numeric prefix + 3-letter USFM book code, e.g.
# "73-JHNeng-kjv2006.usfm". We only need the \id line inside for the code.
WORD_TAG = re.compile(r'\\(\+?w) ([^\\|]*)\|strong="([A-Za-z]\d+)"\\\1\*')


def normalize_strong(raw: str) -> str:
    """"H0430" -> "H430"; "G2316" -> "G2316". Canonical form has no leading
    zero padding, matching how Strong's numbers are conventionally cited."""
    letter, digits = raw[0].upper(), raw[1:]
    return f"{letter}{int(digits)}"


@dataclass
class BookTags:
    code: str
    # "chapter:verse" -> [(word, [strong,...]), ...] in source order
    by_ref: dict = field(default_factory=dict)
    tag_count: int = 0


def parse_usfm_tags(raw: str) -> BookTags | None:
    code = ""
    chapter = 0
    current_verse: int | None = None
    by_ref: dict[str, list[dict]] = {}
    tag_count = 0

    def append(line: str, verse: int) -> None:
        nonlocal tag_count
        # Strip footnotes/cross-references first, same spans USFMParser.cleanUSFM
        # discards from displayed text — the KJV carries no Strong's tags inside
        # them (verified against the full corpus), but this keeps the two
        # channels conceptually aligned if that ever changes upstream.
        text = re.sub(r"\\f .*?\\f\*", "", line, flags=re.S)
        text = re.sub(r"\\x .*?\\x\*", "", text, flags=re.S)
        matches = list(WORD_TAG.finditer(text))
        if not matches:
            return
        key = f"{chapter}:{verse}"
        bucket = by_ref.setdefault(key, [])
        for m in matches:
            word = m.group(2).strip()
            strong = normalize_strong(m.group(3))
            bucket.append({"w": word, "s": [strong]})
            tag_count += 1

    for line in raw.splitlines():
        if line.startswith("\\id "):
            code = line[4:].split(" ", 1)[0].strip()
        elif line.startswith("\\c "):
            try:
                chapter = int(line[3:].strip())
            except ValueError:
                pass
            current_verse = None
        elif line.startswith("\\d ") or line == "\\d":
            if chapter > 0:
                append(line[2:], 0)
        elif line.startswith("\\v "):
            remainder = line[3:]
            parts = remainder.split(" ", 1)
            token = parts[0]
            digits = "".join(ch for ch in token if ch.isdigit())
            if not digits or chapter == 0:
                continue
            verse = int(digits)
            current_verse = verse
            append(parts[1] if len(parts) > 1 else "", verse)
        elif current_verse is not None and (
            line.startswith("\\q") or line.startswith("\\m") or line.startswith("\\p")
        ):
            append(line, current_verse)

    if not code or not by_ref:
        return None
    return BookTags(code=code, by_ref=by_ref, tag_count=tag_count)


def build_kjv_tags(usfm_dir: Path) -> dict[str, BookTags]:
    result: dict[str, BookTags] = {}
    for f in sorted(usfm_dir.glob("*.usfm")):
        raw = f.read_text(encoding="utf-8")
        parsed = parse_usfm_tags(raw)
        if parsed:
            result[parsed.code] = parsed
    return result


# ---------------------------------------------------------------------------
# Strong's dictionary extraction from the raw public-domain XML
# ---------------------------------------------------------------------------

def fetch(url: str, cache_path: Path, allow_network: bool) -> str:
    if cache_path.exists():
        return cache_path.read_text(encoding="utf-8")
    if not allow_network:
        raise SystemExit(f"missing cached source {cache_path} and --no-network was passed")
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=30) as resp:
        data = resp.read().decode("utf-8")
    cache_path.write_text(data, encoding="utf-8")
    return data


def mixed_text(el: ET.Element) -> str:
    """Flattens an entry's mixed-content XML into plain text, expanding the
    inline elements Strong's own e-text uses for cross references."""
    parts: list[str] = []
    if el.text:
        parts.append(el.text)
    for child in el:
        tag = child.tag.split("}")[-1]
        if tag == "strongsref":
            lang = child.get("language", "")
            num = child.get("strongs", "")
            prefix = "G" if lang.upper().startswith("G") else "H"
            if num:
                parts.append(f"{prefix}{int(num)}")
        elif tag == "see":
            lang = child.get("language", "")
            num = child.get("strongs", "")
            prefix = "G" if lang.upper().startswith("G") else "H"
            if num:
                parts.append(f"see {prefix}{int(num)}")
        elif tag in ("greek",):
            parts.append(child.get("unicode") or child.get("translit") or "")
        elif tag in ("latin", "hi"):
            parts.append(mixed_text(child))
        elif tag == "pronunciation":
            parts.append(child.get("strongs") or "")
        elif tag == "w":
            # Hebrew source cross-references a related entry with a self-closing
            # <w src="433" lemma="..."/> inside a note, instead of <strongsref>.
            src = child.get("src")
            if src:
                parts.append(f"H{int(src)}")
            else:
                parts.append(child.get("lemma") or (child.text or ""))
        else:
            parts.append(mixed_text(child))
        if child.tail:
            parts.append(child.tail)
    return "".join(parts)


def clean_ws(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def build_greek_dictionary(xml_text: str) -> dict[str, dict]:
    root = ET.fromstring(xml_text)
    entries = root.find("entries")
    out: dict[str, dict] = {}
    for entry in entries:
        num = entry.get("strongs")
        if not num:
            continue
        key = normalize_strong(f"G{num}")
        greek_el = entry.find("greek")
        pron_el = entry.find("pronunciation")
        deriv_el = entry.find("strongs_derivation")
        def_el = entry.find("strongs_def")
        kjv_el = entry.find("kjv_def")

        lemma = (greek_el.get("unicode") if greek_el is not None else "") or ""
        translit = (greek_el.get("translit") if greek_el is not None else "") or ""
        pronunciation = (pron_el.get("strongs") if pron_el is not None else "") or ""

        derivation = clean_ws(mixed_text(deriv_el)) if deriv_el is not None else ""
        definition = clean_ws(mixed_text(def_el)) if def_el is not None else ""
        combined_def = " ".join(p for p in [derivation, definition] if p) or "(no definition in source)"
        kjv_usage = clean_ws(mixed_text(kjv_el)).lstrip(":-").strip() if kjv_el is not None else ""

        out[key] = {
            "lemma": lemma,
            "translit": translit,
            "pronunciation": pronunciation,
            "definition": combined_def,
        }
        if kjv_usage:
            out[key]["kjvUsage"] = kjv_usage
    return out


def build_hebrew_dictionary(xml_text: str) -> dict[str, dict]:
    root = ET.fromstring(xml_text)
    glossary = root.find(f".//{OSIS_NS}div[@type='glossary']")
    out: dict[str, dict] = {}
    for entry in glossary.findall(f"{OSIS_NS}div[@type='entry']"):
        w_el = entry.find(f"{OSIS_NS}w")
        if w_el is None:
            continue
        wid = w_el.get("ID") or ""
        if not wid.startswith("H"):
            continue
        key = normalize_strong(wid)

        lemma = w_el.get("lemma") or ""
        translit = w_el.get("xlit") or ""
        # NB: this source's `POS` attribute holds the pronunciation string
        # (verified against its own companion JSON export), not part of speech.
        pronunciation = w_el.get("POS") or ""

        notes = {n.get("type"): n for n in entry.findall(f"{OSIS_NS}note")}
        derivation = clean_ws(mixed_text(notes["exegesis"])) if "exegesis" in notes else ""
        list_el = entry.find(f"{OSIS_NS}list")
        senses = []
        if list_el is not None:
            for item in list_el.findall(f"{OSIS_NS}item"):
                text = clean_ws(mixed_text(item))
                if text:
                    senses.append(text)
        sense_text = "; ".join(senses)
        if not sense_text and "explanation" in notes:
            sense_text = clean_ws(mixed_text(notes["explanation"]))
        combined_def = " ".join(p for p in [derivation, sense_text] if p) or "(no definition in source)"
        kjv_usage = clean_ws(mixed_text(notes["translation"])).rstrip(".").strip() if "translation" in notes else ""

        out[key] = {
            "lemma": lemma,
            "translit": translit,
            "pronunciation": pronunciation,
            "definition": combined_def,
        }
        if kjv_usage:
            out[key]["kjvUsage"] = kjv_usage
    return out


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


LICENSE_GREEK = """Throughline Bible — Lexicon licence record: Strong's Greek Dictionary
================================================================

Content: Strong's Greek Dictionary of the New Testament (lemma, transliteration,
pronunciation, derivation, definition, KJV usage), keyed by Strong's number
(e.g. "G2316").

Original work: James Strong, S.T.D., LL.D., "Strong's Exhaustive Concordance
of the Bible" dictionaries, 1890.

Digital edition used: the raw XML e-text at
  https://github.com/openscriptures/strongs
  path: greek/StrongsGreekDictionaryXML_1.4/strongsgreek.xml
  (XML prepared 2006 by Ulrik Petersen from a 1996/1998 ASCII e-text by
  Michael Grier; version 1.4, 2007-09-14)

Licence evidence — quoted verbatim from that XML file's own <prologue>:

    "Dictionary of Greek Words
     taken from
     Strong's Exhaustive Concordance
     by James Strong, S.T.D., LL.D.
     1890

     Public Domain -- Copy Freely"

Deliberately NOT used: openscriptures/strongs also publishes a pre-converted
JSON/JS version of this same dictionary (greek/strongs-greek-dictionary.js)
whose header reads "Copyright 2009, Open Scriptures. CC-BY-SA. Derived from
XML." Throughline does not ship that file or any data copied from it. This
app's strongs-greek.json is built by this repo's own
scripts/build-lexicon.py, which parses the public-domain XML above directly
and recombines its original fields into a new JSON shape — it is an
independent derivation of the 1890 public-domain text, not a copy of Open
Scriptures' CC-BY-SA conversion, and carries no share-alike obligation.

Retrieved: see scripts/build-lexicon.py header comment / build report for the
exact date this pass ran.
"""

LICENSE_HEBREW = """Throughline Bible — Lexicon licence record: Strong's Hebrew Dictionary
=================================================================

Content: Strong's Hebrew (and Biblical Aramaic) Dictionary of the Old
Testament (lemma, transliteration, pronunciation, derivation, definition,
KJV usage), keyed by Strong's number (e.g. "H430").

Original work: James Strong, LL.D., S.T.D., "A Concise Dictionary of the
Words in the Hebrew Bible, with their Renderings in the King James Version",
1894 (from Strong's Exhaustive Concordance of the Bible).

Digital edition used: the raw OSIS XML e-text at
  https://github.com/openscriptures/strongs
  path: hebrew/StrongHebrewG.xml

Licence evidence — quoted verbatim from that XML file's own <header>:

    <work osisWork="Strong" xml:lang="en">
      <title>A Concise Dictionary of the Words in the Hebrew Bible</title>
      <title type="sub">with their Renderings in the King James Version</title>
      <creator role="aut">James Strong, LL.D., S.T.D.</creator>
      <date event="original" type="Gregorian">1894</date>
      <rights>Public Domain</rights>
    </work>

Important exclusion: the same XML file also embeds a `gloss="4a"`-style
attribute on many entries, pointing into Strong's *Theological Wordbook of
the Old Testament* (TWOT). The file's own header declares that work
separately:

    <work osisWork="TWOT" xml:lang="en">
      <title>Theological Wordbook of the Old Testament</title>
      <creator role="aut">Gleason L. Archer and R. Laird Harris</creator>
      <date event="original" type="Gregorian">1980</date>
      <rights type="x-copyright">Copyright (c) 1980 by the Moody Bible
      Institute.</rights>
    </work>

scripts/build-lexicon.py never reads the `gloss` attribute or any TWOT
content. Only the fields declared under the "Strong" work above (lemma,
xlit, POS/pronunciation, and the <list>/<note> senses, derivation and KJV
renderings, all part of the 1894 public-domain dictionary itself) are used.

Deliberately NOT used: openscriptures/strongs also publishes a pre-converted
JSON/JS version of this dictionary (hebrew/strongs-hebrew-dictionary.js)
whose header reads "Copyright 2010, Open Scriptures. CC-BY-SA. Derived from
XML." Throughline does not ship that file or any data copied from it. This
app's strongs-hebrew.json is built by this repo's own
scripts/build-lexicon.py, which parses the public-domain XML above directly
and recombines its original fields into a new JSON shape — it is an
independent derivation of the 1894 public-domain text, not a copy of Open
Scriptures' CC-BY-SA conversion, and carries no share-alike obligation.

Retrieved: see scripts/build-lexicon.py header comment / build report for the
exact date this pass ran.
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--usfm-dir", type=Path, default=Path("scripture-source/kjv"))
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--cache-dir", type=Path, default=Path("/private/tmp/st-lexicon-cache"))
    parser.add_argument("--no-network", action="store_true", help="require cached XML, never fetch")
    args = parser.parse_args()

    out_dir = args.out_dir
    tags_dir = out_dir / "kjv-tags"
    licenses_dir = out_dir / "Licenses"

    books = build_kjv_tags(args.usfm_dir)
    total_tags = sum(b.tag_count for b in books.values())
    for code, book in books.items():
        write_json(tags_dir / f"{code}.json", book.by_ref)

    greek_xml = fetch(GREEK_XML_URL, args.cache_dir / "strongsgreek.xml", not args.no_network)
    hebrew_xml = fetch(HEBREW_XML_URL, args.cache_dir / "StrongHebrewG.xml", not args.no_network)
    greek_dict = build_greek_dictionary(greek_xml)
    hebrew_dict = build_hebrew_dictionary(hebrew_xml)
    write_json(out_dir / "strongs-greek.json", greek_dict)
    write_json(out_dir / "strongs-hebrew.json", hebrew_dict)

    licenses_dir.mkdir(parents=True, exist_ok=True)
    (licenses_dir / "lexicon-greek.txt").write_text(LICENSE_GREEK, encoding="utf-8")
    (licenses_dir / "lexicon-hebrew.txt").write_text(LICENSE_HEBREW, encoding="utf-8")

    # Miss-rate: distinct Strong's numbers used in the KJV tags that have no
    # dictionary entry, both by distinct number and by raw tag occurrence.
    distinct_used: dict[str, int] = {}
    for book in books.values():
        for bucket in book.by_ref.values():
            for tag in bucket:
                for s in tag["s"]:
                    distinct_used[s] = distinct_used.get(s, 0) + 1
    missing = []
    missing_occurrences = 0
    for num, occurrences in distinct_used.items():
        table = greek_dict if num.startswith("G") else hebrew_dict
        if num not in table:
            missing.append(num)
            missing_occurrences += occurrences
    missing.sort()

    report = {
        "books": len(books),
        "total_tags": total_tags,
        "distinct_strong_numbers_used": len(distinct_used),
        "greek_dictionary_entries": len(greek_dict),
        "hebrew_dictionary_entries": len(hebrew_dict),
        "missing_numbers_count": len(missing),
        "missing_tag_occurrences": missing_occurrences,
        "miss_rate_by_occurrence": round(missing_occurrences / total_tags, 6) if total_tags else 0,
        "missing_numbers_sample": missing[:40],
    }
    write_json(out_dir / "lexicon-build-report.json", report)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
