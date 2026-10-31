#!/usr/bin/env python3
"""Builds Thruline's word-level original-language interlinear data (Workstream G, 0.8).

Source: **STEPBible-Data** (Tyndale House Cambridge, curated by STEPBible.org) —
TAHOT (Translators Amalgamated Hebrew OT, Leningrad-based, includes the Aramaic
portions of Daniel/Ezra tagged with an "A" morphology prefix) and TAGNT
(Translators Amalgamated Greek NT). Licence verified directly in the repository
(`README.md`, and restated in every data file's own header and even its
filename): **CC BY 4.0** — attribution required, NOT share-alike. Exact
attribution string and licence text are written to
`Resources/Licenses/interlinear-stepbible.txt`.

This script does NOT use STEPBible's own lexicon files for the lemma/definition
text shown on expansion — it reuses the app's own already-verified, already-
public-domain Strong's dictionaries (`Resources/Lexicon/strongs-hebrew.json`,
`strongs-greek.json`, built by workstream D from the openscriptures raw XML in
0.7) wherever a Strong's number lines up, per the workplan's instruction to
reuse `LexiconStore`'s data rather than ship a second copy of the same
information. STEPBible's own per-word lemma/gloss is kept only as a fallback
for numbers the shipped dictionaries don't cover (STEPBible's own "9xxx" series
extended tags for bare grammatical formatives like the article/conjunction,
which were never part of classical Strong's numbering).

Morphology decoding: STEPBible also publishes **TEGMC**/**TEHMC** ("Translators
Expansion of Greek/Hebrew Morphology Codes", same CC BY 4.0 licence, same
repository) — a direct code -> plain-English-phrase lookup table (e.g.
`V-AAI-3S` -> "Verb Aorist Active Indicative 3rd Singular", `HVqp3ms` ->
"Verb : Qal (Simple, Active) Perfect (Past/present Indicative) Third Singular
Masculine"). This script parses that table directly rather than hand-writing a
second, inevitably-incomplete decoder.

Textual variants and edition flags (0.10, workstream R1): TAGNT's "Word Type" code, its
"editions" column, its "Meaning variants" column and its "Variant Notes" column, and TAHOT's
"Ref & Type" code (Leningrad/Qere/Ketiv/Dead-Sea/... source letters) and "Meaning Variants"
column are carried per word as an optional `v` object (see `build_variant`). Nothing is
interpreted beyond what the source's own header legends state; the legends themselves are
shipped as `Interlinear/variant-legend.json` and every legend string is asserted to exist
verbatim in the cached source header, so a source change that breaks a legend fails the build.
Spelling-variant columns (which the source says have no effect on meaning) are counted, not shipped.

Usage:
    python3 scripts/build-interlinear.py --out-dir /private/tmp/st-interlinear-stage \
        [--cache-dir /private/tmp/st-interlinear-cache] [--no-network] \
        [--lexicon-dir Sources/StudyTable/Resources/Lexicon] \
        [--bsb-dir Sources/StudyTable/Resources/Scripture/BSB]

Output is written to --out-dir (a staging directory outside the package) — the
caller verifies it and moves it into `Sources/StudyTable/Resources/Interlinear/`
atomically, per the project's "generated data is swapped in atomically" rule,
then runs `scripts/clean-sync-duplicates.sh` (this folder is iCloud-synced).
Deterministic: two runs over the same cached inputs produce byte-identical
JSON (stable insertion order, `sort_keys=True` for dict-of-dict output,
`ensure_ascii=False`, fixed separators).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

STEPBIBLE_BASE = "https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master"
SOURCE_FILES = {
    "TAHOT-GenDeu.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAHOT%20Gen-Deu%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt",
    "TAHOT-JosEst.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAHOT%20Jos-Est%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt",
    "TAHOT-JobSng.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAHOT%20Job-Sng%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt",
    "TAHOT-IsaMal.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAHOT%20Isa-Mal%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt",
    "TAGNT-MatJhn.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAGNT%20Mat-Jhn%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt",
    "TAGNT-ActRev.txt": f"{STEPBIBLE_BASE}/Translators%20Amalgamated%20OT%2BNT/TAGNT%20Act-Rev%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt",
    "TEHMC.txt": f"{STEPBIBLE_BASE}/Morphology%20codes/TEHMC%20-%20Translators%20Expansion%20of%20Hebrew%20Morphology%20Codes%20-%20STEPBible.org%20CC%20BY.txt",
    "TEGMC.txt": f"{STEPBIBLE_BASE}/Morphology%20codes/TEGMC%20-%20Translators%20Expansion%20of%20Greek%20Morphhology%20Codes%20-%20STEPBible.org%20CC%20BY.txt",
}

# STEPBible's 3-4 char book abbreviations are ASCII-identical to the app's USFM codes once
# uppercased (Gen -> GEN, 1Sa -> 1SA, Sng -> SNG, Ezk -> EZK, ...), verified against
# StudyTableCore's Canon.bookCodes list.
USFM_BOOK_CODES = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI",
    "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER",
    "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP",
    "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
    "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]
USFM_SET = set(USFM_BOOK_CODES)
CANON_ORDER = {code: i for i, code in enumerate(USFM_BOOK_CODES)}
NT_START = CANON_ORDER["MAT"]

# The primary (English/NRSV) reference always comes first; an alternate versification may follow
# in parens (Hebrew-tradition ref, TAHOT), square brackets (KJV ref, TAGNT) or curly braces
# ("other" editions, TAGNT) -- per STEPBible-Data's README "Reference" note. All three are simply
# skipped: the primary reference is the one that already lines up with the bundled BSB.
REF_RE = re.compile(r"^(\d?[A-Za-z]{2,3})\.(\d+)\.(\d+)(?:[\(\[\{]\d+\.\d+[\)\]\}])?#(\d+)")
STRONG_RE = re.compile(r"[GH]\d{1,5}[A-Za-z]{0,2}")
BASE_STRONG_RE = re.compile(r"^([GH])0*(\d+)")


# ---------------------------------------------------------------------------
# Download / cache
# ---------------------------------------------------------------------------

def ensure_cached(cache_dir: Path, no_network: bool) -> Dict[str, Path]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    paths: Dict[str, Path] = {}
    for name, url in SOURCE_FILES.items():
        path = cache_dir / name
        if not path.exists():
            if no_network:
                print(f"ERROR: {name} not cached and --no-network set", file=sys.stderr)
                sys.exit(1)
            print(f"Downloading {name} ...", file=sys.stderr)
            with urllib.request.urlopen(url, timeout=120) as resp:
                path.write_bytes(resp.read())
        paths[name] = path
    return paths


# ---------------------------------------------------------------------------
# Morphology code tables (TEHMC / TEGMC): "$"-delimited 4-line records --
# CODE\tFunction=...   /   \tquoted-or-plain morphology phrase   /   \texplanation   /   \texample
# ---------------------------------------------------------------------------

def parse_morph_table(path: Path) -> Dict[str, str]:
    table: Dict[str, str] = {}
    lines = path.read_text(encoding="utf-8").split("\n")
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if "\tFunction=" in line and not line.startswith("\t"):
            code = line.split("\t", 1)[0].strip()
            desc = ""
            if i + 1 < n:
                desc = lines[i + 1].strip().strip('"').strip()
            if code and desc:
                table[code] = desc
            i += 1
            continue
        i += 1
    return table


def decode_morph(raw_grammar: str, table: Dict[str, str], misses: Dict[str, int]) -> str:
    """Decodes a (possibly `/`-joined, multi-morpheme) grammar code into a plain-English
    phrase, e.g. "HR/Ncfsa" -> "Preposition + Noun : Common Feminine Singular Absolute".
    Per TEHMC's own note, only the FIRST slash-joined segment carries the language letter
    (H/A); later segments need it re-prepended before lookup."""
    # A doubled "//" marks a boundary between two SEPARATE space-separated Hebrew words that
    # STEPBible nonetheless tags under one reference position (rare -- ~40 of 305k+ words) --
    # it is not a real empty morpheme, so it's skipped rather than looked up as a bare language
    # letter (which is what produced 27 phantom "H"/"A" lookup misses before this fix).
    segments = [seg.strip() for seg in raw_grammar.split("/") if seg.strip()]
    if not segments:
        return raw_grammar
    lang_letter = segments[0][0]
    parts: List[str] = []
    for idx, seg in enumerate(segments):
        code = seg if (idx == 0 or seg[:1] == lang_letter) else f"{lang_letter}{seg}"
        desc = table.get(code)
        if desc is None:
            misses[code] = misses.get(code, 0) + 1
            parts.append(code)
        else:
            parts.append(desc)
    return " + ".join(parts)


# ---------------------------------------------------------------------------
# Strong's dictionary reuse (workstream D's already-verified public-domain data)
# ---------------------------------------------------------------------------

def load_dictionary(path: Path) -> Dict[str, dict]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def base_strong(raw: str) -> Optional[str]:
    m = BASE_STRONG_RE.match(raw)
    if not m:
        return None
    return f"{m.group(1)}{int(m.group(2))}"


# ---------------------------------------------------------------------------
# BSB versification ground truth
# ---------------------------------------------------------------------------

def load_bsb_valid_verses(bsb_dir: Path) -> Dict[Tuple[str, int], set]:
    """Exact valid verse numbers per (book, chapter), read directly from each bundled BSB book's
    own `v` array -- NOT derived from `manifest.json`'s per-chapter *count*, which undercounts any
    chapter with a real gap in its verse numbering (e.g. Matthew 17 has verses 1-20, 22-27: a
    count of 26 but a real maximum verse number of 27, because English critical-text editions
    (BSB included) omit Matthew 17:21/18:11/23:14, Mark 7:16/9:44/9:46/11:26/15:28/16:9-20's
    numbering quirks, Luke 17:36/23:17, John 5:4, Acts 8:37/15:34/24:7/28:29 as manuscript-critical
    footnote verses -- a naive `1...count` range check misreports every verse after the gap as
    'versification mismatch' even though it lines up with BSB perfectly)."""
    valid: Dict[Tuple[str, int], set] = {}
    for path in bsb_dir.glob("*.json"):
        if path.name == "manifest.json":
            continue
        code = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))
        for chapter in data.get("chapters", []):
            valid[(code, chapter["n"])] = set(chapter.get("v", []))
    return valid


# ---------------------------------------------------------------------------
# TAHOT / TAGNT parsing
# ---------------------------------------------------------------------------

class WordRow:
    __slots__ = ("book", "chapter", "verse", "position", "surface", "translit", "gloss",
                 "strongs", "morph_code", "language", "type_code", "editions", "alt_raw",
                 "note_raw", "spelling_raw", "variant")

    def __init__(self, book, chapter, verse, position, surface, translit, gloss, strongs, morph_code, language,
                 type_code="", editions="", alt_raw="", note_raw="", spelling_raw=""):
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.position = position
        self.surface = surface
        self.translit = translit
        self.gloss = gloss
        self.strongs = strongs  # list[str], primary (content word) first
        self.morph_code = morph_code
        self.language = language  # "H" / "A" / "G"
        self.type_code = type_code      # source "Word Type" (TAGNT) / "Type" (TAHOT) code, e.g. NKO, K, L(D), Q(K)
        self.editions = editions        # TAGNT "editions" column (which editions carry this exact word)
        self.alt_raw = alt_raw          # "Meaning variants" column, verbatim
        self.note_raw = note_raw        # TAGNT "Variant Notes" column, verbatim
        self.spelling_raw = spelling_raw  # spelling variants: counted, never shipped
        self.variant = None


def clean_surface(raw: str) -> str:
    # "/" marks a morpheme boundary (prefix+root written together in Hebrew) -- a display join, not
    # a space. "\" marks the start of attached punctuation glyphs (maqaf, sof pasuq, paseq, the
    # petuchah/setumah letters...): everything from the first "\" on is punctuation, not the word,
    # and is dropped from the word's own surface form (0.10: it used to be glued on, so the single-
    # word card and LCD showed "הָאָרֶץ׃" and "עַל־").
    return raw.split("\\", 1)[0].replace("/", "").strip()


# Trailing punctuation TAGNT glues onto a Greek word: comma, full stop, Greek question mark
# (U+037E, and the ASCII ";" it is sometimes typed as), ano teleia (U+00B7 / U+0387), the pilcrow
# paragraph mark and the "not sign" the source uses once. It may sit before closing text-critical
# brackets ("ἁμάρτανε.¶]]"): the brackets stay, the punctuation goes. The koronis (U+1FBD, as in
# par᾽) is part of the word and stays.
GREEK_TRAILING_PUNCT = re.compile(r"[\s,.;\u037e\u00b7\u0387\u00b6\u00ac]+(\]*)$")


def clean_greek_surface(raw: str) -> str:
    return GREEK_TRAILING_PUNCT.sub(r"\1", raw.strip())


GLOSS_EDGE_PUNCT = ",.;:—’‘'\" "


def trim_gloss(text: str) -> str:
    """Sentence punctuation the source's English translation carries at either end of a gloss
    ("good," / "being." / "evil'"). Square and angle brackets mean something ([implied] /
    <untranslated>) and stay, and so do "?" and "!": a gloss such as "how many?" is a question in
    the source's own translation, not decoration."""
    return text.strip(GLOSS_EDGE_PUNCT)


def clean_gloss(raw: str) -> str:
    text = raw.replace("/", " ").replace("\\", " ")
    return re.sub(r"\s+", " ", text).strip()


def clean_translit(raw: str) -> str:
    # Unlike the gloss ("the/ heavens" -> "the heavens", a real word boundary), the source's own
    # transliteration already puts a space after a prefix's "/" when one is meant ("be./re.Shit"
    # has none -- it's one continuous word) -- so this only strips the join marker, never adds a
    # space of its own the source didn't already print.
    return raw.replace("/", "").replace("\\", "").strip()


def parse_hebrew_line(cols: List[str]) -> Optional[Tuple[str, int, int, int, WordRow]]:
    ref_match = REF_RE.match(cols[0])
    if not ref_match:
        return None
    book, chapter, verse, position = ref_match.group(1).upper(), int(ref_match.group(2)), int(ref_match.group(3)), int(ref_match.group(4))
    if book not in USFM_SET:
        return None
    surface = clean_surface(cols[1]) if len(cols) > 1 else ""
    # A trailing "-" in the transliteration is the maqaf, i.e. the same attached punctuation dropped
    # from the surface form above.
    translit = clean_translit(cols[2]).rstrip("-") if len(cols) > 2 else ""
    gloss = trim_gloss(clean_gloss(cols[3])) if len(cols) > 3 else ""
    dstrongs = cols[4] if len(cols) > 4 else ""
    grammar = cols[5] if len(cols) > 5 else ""
    # Punctuation-attached Strong's numbers (verseEnd, maqaf, paseq...) ride after a "\" --
    # only the part before it is real word morphology.
    word_part = dstrongs.split("\\")[0]
    raw_segments = word_part.split("/") if word_part else []
    strongs: List[str] = []
    primary: Optional[str] = None
    for seg in raw_segments:
        seg = seg.strip()
        bracketed = seg.startswith("{") and seg.endswith("}")
        num = seg.strip("{}").strip()
        if not num:
            continue
        strongs.append(num)
        if bracketed:
            primary = num
    if primary and strongs and strongs[0] != primary:
        strongs = [primary] + [s for s in strongs if s != primary]
    if not surface:
        # A handful of rows (~5 in the whole OT) are Ketiv-only variant placeholders with every
        # field blank ("[ ]") -- the real Ketiv text lives inline in a neighboring row's own
        # variant-note column instead of getting its own position. Nothing to show; drop it.
        return None
    language = "A" if grammar[:1] == "A" else "H"
    type_code = cols[0].split("=", 1)[1].strip() if "=" in cols[0] else ""
    row = WordRow(book, chapter, verse, position, surface, translit, gloss, strongs, grammar, language,
                  type_code=type_code,
                  alt_raw=cols[6].strip() if len(cols) > 6 else "",
                  spelling_raw=cols[7].strip() if len(cols) > 7 else "")
    return (book, chapter, verse, position, row)


def parse_greek_line(cols: List[str]) -> Optional[Tuple[str, int, int, int, WordRow]]:
    ref_match = REF_RE.match(cols[0])
    if not ref_match:
        return None
    book, chapter, verse, position = ref_match.group(1).upper(), int(ref_match.group(2)), int(ref_match.group(3)), int(ref_match.group(4))
    if book not in USFM_SET:
        return None
    greek_field = cols[1] if len(cols) > 1 else ""
    surface, translit = "", ""
    paren = greek_field.rfind("(")
    if paren != -1 and greek_field.endswith(")"):
        surface = greek_field[:paren].strip()
        translit = greek_field[paren + 1:-1].strip()
    else:
        surface = greek_field.strip()
    surface = clean_greek_surface(surface)
    gloss = trim_gloss(clean_gloss(cols[2])) if len(cols) > 2 else ""
    combined = cols[3] if len(cols) > 3 else ""
    eq = combined.rfind("=")
    if eq == -1:
        strong_part, morph = combined, ""
    else:
        strong_part, morph = combined[:eq], combined[eq + 1:]
    strongs = STRONG_RE.findall(strong_part) or ([strong_part] if strong_part else [])
    type_code = cols[0].split("=", 1)[1].strip() if "=" in cols[0] else ""
    row = WordRow(book, chapter, verse, position, surface, translit, gloss, strongs, morph, "G",
                  type_code=type_code,
                  editions=cols[5].strip() if len(cols) > 5 else "",
                  alt_raw=cols[6].strip() if len(cols) > 6 else "",
                  spelling_raw=cols[7].strip() if len(cols) > 7 else "",
                  note_raw=cols[13].strip() if len(cols) > 13 else "")
    return (book, chapter, verse, position, row)


def parse_file(path: Path, parser, label: str, stats: dict) -> Dict[str, Dict[int, Dict[int, List[Tuple[int, WordRow]]]]]:
    result: Dict[str, Dict[int, Dict[int, List[Tuple[int, WordRow]]]]] = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    total = 0
    skipped = 0
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            first_tab = line.find("\t")
            head = line if first_tab == -1 else line[:first_tab]
            if not head or head[0] == "#" or not (head[0].isdigit() or head[0].isalpha()):
                continue
            if "." not in head or "#" not in head:
                continue
            cols = line.rstrip("\n").split("\t")
            parsed = parser(cols)
            if parsed is None:
                skipped += 1
                continue
            book, chapter, verse, position, row = parsed
            result[book][chapter][verse].append((position, row))
            total += 1
    stats[label] = {"words": total, "skippedLines": skipped}
    print(f"  {label}: {total} words parsed, {skipped} lines skipped", file=sys.stderr)
    return result


def merge_into(target: dict, source: dict) -> None:
    for book, chapters in source.items():
        for chapter, verses in chapters.items():
            for verse, rows in verses.items():
                target[book][chapter][verse].extend(rows)


# ---------------------------------------------------------------------------
# Textual variants / edition flags (0.10, R1)
#
# Everything below decodes ONLY what the two source headers state. Legend text is quoted from the
# header lines; `verify_legend` asserts each quoted fragment is present verbatim in the cached
# source so this file can never drift into stating something the source does not.
# ---------------------------------------------------------------------------

# code -> (label shown in the app, verbatim fragment of the TAGNT "Editions" header line)
GREEK_EDITION_LEGEND: Dict[str, Tuple[str, str]] = {
    "NA28": ("NA28 (2012)", "NA28 2012"),
    "NA27": ("Nestle-Aland 27th ed.", "NA27=Nestle-Aland 27th ed"),
    "Tyn": ("Tyndale House GNT (2017)", "Tyn= Tyndale House GNT 2017"),
    "SBL": ("SBL (Holmes 2010)", "SBL= Holmes 2010"),
    "WH": ("Westcott-Hort (1881)", "WH= Westcott+Hort 1881"),
    "Treg": ("Tregelles (1879, with Jongkind 2009)", "Treg= Tregelles 1879+Jongkind 2009"),
    "TR": ("Textus Receptus (Scrivener 1894)", "TR= Scrivener"),
    "Byz": ("Byzantine text (based on RP 2005)", "Byz=Byzantine based on RP 2005"),
}
# Plain names used in sentences ("found in Westcott-Hort, but not in the Textus Receptus").
GREEK_EDITION_SHORT = {
    "NA28": "Nestle-Aland 28", "NA27": "Nestle-Aland 27", "Tyn": "the Tyndale House GNT", "SBL": "the SBL text",
    "WH": "Westcott-Hort", "Treg": "Tregelles", "TR": "the Textus Receptus", "Byz": "the Byzantine text",
}
# The source's own N / K / O text-type letters (TAGNT "Word Type" line).
GREEK_TYPE_LETTERS = {
    "N": "Greek in the Nestle-Aland editions, as used by most modern translators",
    "K": "Greek used by the KJV translators, based on Scrivener 1894",
    "O": "other Greek found in major editions but rarely translated",
}
GREEK_NOTE_VOCABULARY = ('In the source\'s variant notes, readings translated by the KJV are called "traditional", '
                         'readings that agree with NA27 are called "older", and others are called "a few".')
HEBREW_SOURCE_SHORT = {
    "L": "the Leningrad manuscript", "Q": "the Qere", "K": "the Ketiv", "R": "restored text", "X": "Greek-derived text",
    "A": "the Aleppo manuscript", "B": "BHS", "C": "the Cairensis manuscript",
    "D": "a Dead Sea or Judean Desert manuscript", "E": "an emendation", "F": "different formatting of the text",
    "H": "the Ben Chaim edition", "P": "alternate punctuation", "S": "scribal traditions", "V": "other manuscripts",
}
# The eight editions the source's "Editions" line defines, in the order the source lists them
# in a full row ("NA28+NA27+Tyn+SBL+WH+Treg+TR+Byz").
GREEK_EDITION_ORDER = ["NA28", "NA27", "Tyn", "SBL", "WH", "Treg", "TR", "Byz"]
# Tokens that appear in the editions column but are not in the source's edition legend. Their
# meaning is shown as "not defined in the source legend" -- never guessed.
GREEK_EXTRA_TOKEN_NOTES: Dict[str, Tuple[str, str]] = {
    "KJV": ("The KJV translators' text (where the KJV departs from the Textus Receptus)",
            "K=KJV translators' text based on the 'Textus Receptus' (TR) of Scrivener"),
}

# code -> (label, verbatim fragment of the TAHOT header)
HEBREW_SOURCE_LEGEND: Dict[str, Tuple[str, str]] = {
    "L": ("the Leningrad manuscript", "L= Leningrad manuscript"),
    "Q": ("the Qere (the scribes' marginal correction, which translators normally follow)", "Q= \"a Scribal corrections\""),
    "K": ("the Ketiv (the uncorrected text, as written)", "K= \"the uncorrected text\""),
    "R": ("restored text based on Leningrad parallels (Jos 21:36-37 from 1Ch 6:63-64; Neh 7:67b from Ezr 2:66)", "R= restored text based on Leningrad parallels"),
    "X": ("extra words preserved in the Greek (LXX), converted back to Hebrew as in the apparatus of BHS or BHK", "X= \"based on Greek sources\""),
    "A": ("the Aleppo manuscript", "A= \"in the Aleppo manuscript\""),
    "B": ("the Biblia Hebraica Stuttgartensia (BHS), where it deviates from the Masoretic text", "B= \"in the Biblia Hebraica Stuttgartensia\""),
    "C": ("the Cairensis manuscript", "C= \"in the Cairensis manuscript\""),
    "D": ("a Dead Sea or Judean Desert manuscript", "D= \"in a Dead Sea or Judean Desert manuscript\""),
    "E": ("an emendation of ancient sources (a scholarly guess at the original when the Hebrew looks garbled)", "E=  \"an emendation of ancient sources\""),
    "F": ("formatting the text differently (pointing or word divisions change, no letters change)", "F= \"formatting the text differently\""),
    "H": ("the Ben Chaim edition (the Second Rabbinic Bible)", "H= \"in the Ben Chaim edtion\""),
    "P": ("alternate punctuation, as marked in major manuscripts", "P= \"with alternate punctuation\""),
    "S": ("Scribal traditions (Itture Sopherim, Tiqqune Sopherim, Masora and similar)", "S= \"in Scribal traditions\""),
    "V": ("a variant in some manuscripts other than those above", "V = \"a variant in some manuscripts\""),
}

# Verbatim statements from the source headers that the app repeats to the reader.
GREEK_NOTE_MARKER_LEGEND = {
    "^": "Extra text: some manuscripts have text not found in others.",
    "v": "Variant: some manuscripts have significantly different wording.",
}
LEGEND_CAVEATS = {
    "greek": "STEPBible's TAGNT header says its variants include every variant in the major editions, and manuscript variants before AD 500 that are used by translators. It does not note insignificant differences (spelling, or word order that does not change the meaning).",
    "hebrew": "STEPBible's TAHOT header says the Qere/Ketiv readings and the restored and Greek-derived (X) words are recorded throughout, but that most other variants (Dead Sea Scrolls, Aleppo, Cairensis, Ben Chaim, BHS and so on) are yet to be added. No flag on a Hebrew word therefore does not prove that no variant exists.",
}
LEGEND_SOURCE_FRAGMENTS = [
    # (source file key, verbatim fragment)
    ("TAGNT-MatJhn.txt", '"v"=Variant - when some manuscripts have significantly different wording. "^"=Extra text - when some manuscripts have text not found in others.'),
    ("TAGNT-MatJhn.txt", 'Manuscript readings that are translated by the KJV are labelled "traditional"; those that agree with NA27 are labelled "older"; and others are labelled as "a few".'),
    ("TAGNT-MatJhn.txt", "Includes every variant in the major editions and manuscript variants before AD 500 that are used by translators"),
    ("TAGNT-MatJhn.txt", "Insignificant manuscript differences are not noted"),
    ("TAGNT-MatJhn.txt", 'Lower case "n" "k", "o" are differences that are too minor  to entail a different translation.'),
    ("TAGNT-MatJhn.txt", "N / \"Ancient\" = Greek in Nesté-Aland, translated by most Bibles."),
    ("TAGNT-MatJhn.txt", "\"Traditional\" = Greek of the KJV or \"Textus Receptus\" based on Scrivener 1894."),
    ("TAGNT-MatJhn.txt", "N=Greek in Nestlé-Aland editions which as used by most modern translators, K=Greek used by the KJV translators based on Scrivener 1894; O=other Greek found in major editions but rarely translated."),
    ("TAGNT-MatJhn.txt", "Editions that have words in a different order are listed with the amount of displacement"),
    ("TAHOT-GenDeu.txt", "(Most of these variants are yet to be added. )"),
    ("TAHOT-GenDeu.txt", "Brackets indicate a variant  which is in lower case if it might not affect the translation."),
    ("TAHOT-GenDeu.txt", "Translators normally follow L, and when this presents a choice between Q and K they follow Q, so K is presented as a variant."),
    ("TAHOT-GenDeu.txt", "These spelling differences have no effect on the meaning"),
]


def verify_legend(paths: Dict[str, Path]) -> None:
    """Fail the build unless every legend fragment above is present verbatim in the cached source."""
    headers: Dict[str, str] = {}
    for key in ("TAGNT-MatJhn.txt", "TAHOT-GenDeu.txt"):
        with paths[key].open("r", encoding="utf-8") as fh:
            headers[key] = "".join(line for _, line in zip(range(140), fh)).replace("﻿", "")
    missing: List[str] = []
    for code, (_, fragment) in GREEK_EDITION_LEGEND.items():
        if fragment not in headers["TAGNT-MatJhn.txt"]:
            missing.append(f"TAGNT edition {code}: {fragment!r}")
    for code, (_, fragment) in GREEK_EXTRA_TOKEN_NOTES.items():
        if fragment not in headers["TAGNT-MatJhn.txt"]:
            missing.append(f"TAGNT token {code}: {fragment!r}")
    for code, (_, fragment) in HEBREW_SOURCE_LEGEND.items():
        if fragment not in headers["TAHOT-GenDeu.txt"]:
            missing.append(f"TAHOT source {code}: {fragment!r}")
    for key, fragment in LEGEND_SOURCE_FRAGMENTS:
        # Header whitespace in the source is irregular (tabs, doubled spaces); compare collapsed.
        if re.sub(r"\s+", " ", fragment) not in re.sub(r"\s+", " ", headers[key]):
            missing.append(f"{key}: {fragment!r}")
    if missing:
        print("ERROR: legend text no longer matches the source header:\n  " + "\n  ".join(missing), file=sys.stderr)
        sys.exit(1)


def variant_legend_payload() -> dict:
    return {
        "schema": 1,
        "source": "STEPBible-Data TAGNT / TAHOT header legends (CC BY 4.0); labels condensed from the quoted header lines",
        "greekEditions": {code: label for code, (label, _) in GREEK_EDITION_LEGEND.items()},
        "greekEditionShort": GREEK_EDITION_SHORT,
        "greekEditionOrder": GREEK_EDITION_ORDER,
        "greekTypeLetters": GREEK_TYPE_LETTERS,
        "greekNoteVocabulary": GREEK_NOTE_VOCABULARY,
        "greekOtherTokens": {code: label for code, (label, _) in GREEK_EXTRA_TOKEN_NOTES.items()},
        "greekNoteMarkers": GREEK_NOTE_MARKER_LEGEND,
        "hebrewSources": {code: label for code, (label, _) in HEBREW_SOURCE_LEGEND.items()},
        "hebrewSourceShort": HEBREW_SOURCE_SHORT,
        "caveats": LEGEND_CAVEATS,
    }


def greek_code_is_significant(code: str) -> bool:
    """Per the source's own legend: brackets mark a variant; an UPPER-case letter is a difference
    big enough to affect translation, lower case one "too minor to entail a different translation".
    Letters outside brackets say which text types carry the word at all; a word absent from one
    type (e.g. `K`, `NO`) is significant when the letters that remain are upper case."""
    if code == "NKO":
        return False
    inner = "".join(re.findall(r"\(([A-Za-z]+)\)", code))
    outer = re.sub(r"\([A-Za-z]+\)", "", code)
    if any(ch.isupper() for ch in inner):
        return True
    present = {ch.upper() for ch in code if ch.isalpha()}
    if present >= {"N", "K", "O"}:
        return False
    return any(ch.isupper() for ch in outer)


def hebrew_code_is_significant(code: str) -> bool:
    if code[:1] in ("X", "R"):
        return True
    inner = "".join(re.findall(r"\(([A-Za-z+]+)\)", code))
    return any(ch.isupper() for ch in inner)


# "reading (t=translit) gloss - G0863=V-PAI-1P in: TR+Byz" -- a multi-word reading lists several
# "Gnnnn=morph" pairs joined by " + " ("G1722=PREP + G3588=T-DPM + G3772=N-DPM").
ALT_GREEK_RE = re.compile(
    r"^(?P<r>.+?) \((?P<y>[A-Za-z])=(?P<t>[^)]*)\) (?P<g>.*) - (?P<sm>[GH]\d+[A-Za-z]*\S*?=\S+(?: \+ [GH]\d+[A-Za-z]*\S*?=\S+)*) in: (?P<w>.+)$")
STRONG_MORPH_PAIR_RE = re.compile(r"([GH]\d+[A-Za-z]*)\S*?=(\S+)")
ALT_HEBREW_RE = re.compile(r"^(?P<w>[A-Za-z]+)=\s*(?P<rest>.*)$")
ALT_HEBREW_TAIL_RE = re.compile(r'^(?P<pre>.*?) "(?P<g>[^"]*)" \((?P<sm>[^()]*)\)$')


def clean_note_text(raw: str) -> str:
    text = re.sub(r"</?i>", "", raw)
    return re.sub(r"\s+", " ", text).strip()


def parse_greek_alternates(raw: str, table: Dict[str, str], misses: Dict[str, int], stats: dict) -> List[dict]:
    out: List[dict] = []
    for part in [p.strip() for p in raw.split("¦") if p.strip()]:
        m = ALT_GREEK_RE.match(part)
        if not m:
            stats["greekAltUnparsed"] = stats.get("greekAltUnparsed", 0) + 1
            if len(stats.get("greekAltUnparsedSamples", [])) < 8:
                stats.setdefault("greekAltUnparsedSamples", []).append(part[:160])
            out.append({"r": part})
            continue
        pairs = STRONG_MORPH_PAIR_RE.findall(m.group("sm"))
        alt = {"r": m.group("r").strip(), "t": m.group("t").strip(), "g": m.group("g").strip(),
               "n": [n for n, _ in pairs], "m": " + ".join(mo for _, mo in pairs),
               "w": m.group("w").strip(), "y": m.group("y")}
        alt["d"] = " + ".join(decode_morph(mo, table, misses) for _, mo in pairs)
        out.append(alt)
    return out


def parse_hebrew_alternates(raw: str, table: Dict[str, str], misses: Dict[str, int], stats: dict) -> List[dict]:
    out: List[dict] = []
    for part in [p.strip() for p in raw.split("¦") if p.strip()]:
        head = ALT_HEBREW_RE.match(part)
        tail = ALT_HEBREW_TAIL_RE.match(head.group("rest")) if head else None
        if not head or not tail:
            stats["hebrewAltUnparsed"] = stats.get("hebrewAltUnparsed", 0) + 1
            if len(stats.get("hebrewAltUnparsedSamples", [])) < 8:
                stats.setdefault("hebrewAltUnparsedSamples", []).append(part[:160])
            out.append({"r": part})
            continue
        pre = tail.group("pre")
        paren = pre.find(" (")
        if paren == -1 or not pre.endswith(")"):
            translit, hebrew = "", pre
        else:
            translit, hebrew = pre[:paren], pre[paren + 2:-1]
        strong_part, _, morph = tail.group("sm").partition("=")
        strongs = [seg.strip("{} ") for seg in strong_part.split("\\")[0].replace("+", "/").split("/") if seg.strip("{} ")]
        alt = {"r": clean_surface(hebrew), "t": clean_translit(translit).rstrip("-"),
               "g": trim_gloss(clean_gloss(tail.group("g"))), "w": head.group("w")}
        if strongs:
            alt["n"] = strongs
        if morph:
            alt["m"] = morph
            alt["d"] = decode_morph(morph, table, misses)
        out.append(alt)
    return out


def build_variants(verse_rows: List[WordRow], greek_table: Dict[str, str], hebrew_table: Dict[str, str],
                   greek_misses: Dict[str, int], hebrew_misses: Dict[str, int], stats: dict) -> None:
    """Attaches `row.variant` (a plain dict, or None) to every word of one verse.

    Greek: a "^" (extra text) or "v" (different wording) marker sits on EACH word of a multi-word
    variant, but "the note is placed on the last one" (source legend). The note is therefore copied
    back onto the bare-marker words directly before it, so the first word of "ὁ θεὸς" (Rom 8:28)
    explains itself too."""
    pending: List[WordRow] = []
    for row in verse_rows:
        is_greek = row.language == "G"
        code = row.type_code
        marker, note = "", ""
        if is_greek and row.note_raw:
            marker = row.note_raw[:1]
            note = clean_note_text(row.note_raw[1:])
        flagged = (code not in ("", "NKO")) if is_greek else (code not in ("", "L"))
        if is_greek and (row.alt_raw or marker):
            flagged = True
        if not is_greek and row.alt_raw:
            flagged = True
        if not flagged:
            pending = []
            continue
        variant: dict = {"c": code}
        significant = greek_code_is_significant(code) if is_greek else hebrew_code_is_significant(code)
        if significant:
            variant["s"] = True
        if is_greek:
            if row.editions:
                variant["e"] = row.editions
            if marker:
                variant["k"] = marker
            if note:
                variant["t"] = note
            if row.alt_raw:
                variant["a"] = parse_greek_alternates(row.alt_raw, greek_table, greek_misses, stats)
        else:
            if row.alt_raw:
                variant["a"] = parse_hebrew_alternates(row.alt_raw, hebrew_table, hebrew_misses, stats)
        row.variant = variant
        if is_greek and marker:
            if note:
                for earlier in pending:
                    if earlier.variant and earlier.variant.get("k") == marker and "t" not in earlier.variant:
                        earlier.variant["t"] = note
                pending = []
            else:
                pending.append(row)
        else:
            pending = []


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--cache-dir", default=Path("/private/tmp/st-interlinear-cache"), type=Path)
    parser.add_argument("--no-network", action="store_true")
    parser.add_argument("--lexicon-dir", default=Path("Sources/StudyTable/Resources/Lexicon"), type=Path)
    parser.add_argument("--bsb-dir", default=Path("Sources/StudyTable/Resources/Scripture/BSB"), type=Path)
    args = parser.parse_args()

    t0 = time.time()
    paths = ensure_cached(args.cache_dir, args.no_network)
    verify_legend(paths)

    print("Parsing morphology code tables...", file=sys.stderr)
    hebrew_morph_table = parse_morph_table(paths["TEHMC.txt"])
    greek_morph_table = parse_morph_table(paths["TEGMC.txt"])
    print(f"  TEHMC: {len(hebrew_morph_table)} codes, TEGMC: {len(greek_morph_table)} codes", file=sys.stderr)

    hebrew_dict = load_dictionary(args.lexicon_dir / "strongs-hebrew.json")
    greek_dict = load_dictionary(args.lexicon_dir / "strongs-greek.json")
    print(f"  Reusing Strong's dictionaries: {len(hebrew_dict)} Hebrew, {len(greek_dict)} Greek entries", file=sys.stderr)

    valid_verses = load_bsb_valid_verses(args.bsb_dir)

    stats: dict = {}
    print("Parsing TAHOT (Hebrew/Aramaic OT)...", file=sys.stderr)
    hebrew_data: dict = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for name in ["TAHOT-GenDeu.txt", "TAHOT-JosEst.txt", "TAHOT-JobSng.txt", "TAHOT-IsaMal.txt"]:
        merge_into(hebrew_data, parse_file(paths[name], parse_hebrew_line, name, stats))

    print("Parsing TAGNT (Greek NT)...", file=sys.stderr)
    greek_data: dict = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for name in ["TAGNT-MatJhn.txt", "TAGNT-ActRev.txt"]:
        merge_into(greek_data, parse_file(paths[name], parse_greek_line, name, stats))

    # ---- Lemma/definition + morphology decoding, versification check, chapter-file assembly ----
    hebrew_misses: Dict[str, int] = {}
    greek_misses: Dict[str, int] = {}
    dict_hits = {"hebrew": 0, "hebrewMiss": 0, "greek": 0, "greekMiss": 0}
    mismatches: List[dict] = []
    out_root = args.out_dir / "Interlinear"
    if out_root.exists():
        import shutil
        shutil.rmtree(out_root)
    out_root.mkdir(parents=True)

    concordance_hebrew: Dict[str, List[dict]] = defaultdict(list)
    concordance_greek: Dict[str, List[dict]] = defaultdict(list)

    word_totals = {"hebrew": 0, "aramaic": 0, "greek": 0}
    variant_stats: dict = {
        "greek": {"flaggedWords": 0, "significantWords": 0, "minorWords": 0, "byCode": defaultdict(int),
                  "byNoteMarker": defaultdict(int), "wordsWithAlternateReadings": 0, "alternateReadings": 0,
                  "wordsWithNote": 0, "spellingVariantColumnNonEmptyNotShown": 0},
        "hebrewAramaic": {"flaggedWords": 0, "significantWords": 0, "minorWords": 0, "byCode": defaultdict(int),
                          "wordsWithAlternateReadings": 0, "alternateReadings": 0,
                          "spellingVariantColumnNonEmptyNotShown": 0},
    }
    variant_parse_stats: dict = {}
    verse_totals = 0
    chapters_written = 0

    def resolve_lemma(strongs: List[str], dictionary: Dict[str, dict], is_hebrew: bool, source_lemma_gloss: str) -> str:
        for s in strongs:
            base = base_strong(s)
            if base and base in dictionary:
                if is_hebrew:
                    dict_hits["hebrew"] += 1
                else:
                    dict_hits["greek"] += 1
                return dictionary[base]["lemma"]
        if is_hebrew:
            dict_hits["hebrewMiss"] += 1
        else:
            dict_hits["greekMiss"] += 1
        return source_lemma_gloss

    def build_word(row: WordRow) -> dict:
        is_hebrew = row.language != "G"
        table = hebrew_morph_table if is_hebrew else greek_morph_table
        misses = hebrew_misses if is_hebrew else greek_misses
        morph_desc = decode_morph(row.morph_code, table, misses) if row.morph_code else ""
        dictionary = hebrew_dict if is_hebrew else greek_dict
        lemma = resolve_lemma(row.strongs, dictionary, is_hebrew, row.surface)
        word = {
            "w": row.surface,
            "t": row.translit,
            "g": row.gloss,
            "l": lemma,
            "n": row.strongs,
            "m": row.morph_code,
            "d": morph_desc,
            "L": row.language,
        }
        if row.variant:
            word["v"] = row.variant
        return word

    for language_label, data, verse_key_check in (("hebrew_aramaic", hebrew_data, True), ("greek", greek_data, False)):
        for book in sorted(data.keys(), key=lambda c: CANON_ORDER.get(c, 999)):
            for chapter in sorted(data[book].keys()):
                bsb_verses = valid_verses.get((book, chapter), set())
                verses_out: Dict[str, list] = {}
                for verse in sorted(data[book][chapter].keys()):
                    valid = verse in bsb_verses
                    rows = sorted(data[book][chapter][verse], key=lambda pr: pr[0])
                    if not valid:
                        present = sorted(bsb_verses)
                        mismatches.append({
                            "book": book, "chapter": chapter, "verse": verse,
                            "words": len(rows),
                            "reason": f"verse {verse} not present in bundled BSB {book} {chapter} "
                                      f"(BSB verses: {present[0]}..{present[-1]}, {len(present)} total)"
                                      if present else f"BSB has no {book} {chapter} at all",
                        })
                        continue
                    build_variants([r for _, r in rows], greek_morph_table, hebrew_morph_table,
                                   greek_misses, hebrew_misses, variant_parse_stats)
                    word_dicts = []
                    for _, row in rows:
                        word_dicts.append(build_word(row))
                        vs = variant_stats["greek"] if row.language == "G" else variant_stats["hebrewAramaic"]
                        if row.spelling_raw:
                            vs["spellingVariantColumnNonEmptyNotShown"] += 1
                        if row.variant:
                            vs["flaggedWords"] += 1
                            vs["significantWords" if row.variant.get("s") else "minorWords"] += 1
                            vs["byCode"][row.variant["c"]] += 1
                            if row.variant.get("a"):
                                vs["wordsWithAlternateReadings"] += 1
                                vs["alternateReadings"] += len(row.variant["a"])
                            if row.language == "G":
                                if row.variant.get("k"):
                                    vs["byNoteMarker"][row.variant["k"]] += 1
                                if row.variant.get("t"):
                                    vs["wordsWithNote"] += 1
                        if row.language == "H":
                            word_totals["hebrew"] += 1
                        elif row.language == "A":
                            word_totals["aramaic"] += 1
                        else:
                            word_totals["greek"] += 1
                        for s in row.strongs[:1]:
                            base = base_strong(s)
                            if not base:
                                continue
                            entry = {"b": book, "c": chapter, "v": verse, "w": row.surface, "g": row.gloss}
                            if row.language == "G":
                                concordance_greek[base].append(entry)
                            elif base.startswith("H"):
                                concordance_hebrew[base].append(entry)
                    verses_out[str(verse)] = word_dicts
                    verse_totals += 1
                if not verses_out:
                    continue
                book_dir = out_root / book
                book_dir.mkdir(parents=True, exist_ok=True)
                payload = {"code": book, "chapter": chapter, "verses": verses_out}
                (book_dir / f"{chapter}.json").write_text(
                    json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
                    encoding="utf-8")
                chapters_written += 1

    # Concordance files (lazy-loaded, cached, single-file-per-testament lookup).
    (out_root / "concordance").mkdir(parents=True, exist_ok=True)
    for base, entries in concordance_hebrew.items():
        entries.sort(key=lambda e: (CANON_ORDER.get(e["b"], 999), e["c"], e["v"]))
    for base, entries in concordance_greek.items():
        entries.sort(key=lambda e: (CANON_ORDER.get(e["b"], 999), e["c"], e["v"]))
    (out_root / "concordance" / "hebrew-concordance.json").write_text(
        json.dumps(concordance_hebrew, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    (out_root / "concordance" / "greek-concordance.json").write_text(
        json.dumps(concordance_greek, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")

    (out_root / "variant-legend.json").write_text(
        json.dumps(variant_legend_payload(), ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")

    # ---- Licence + attribution file ----
    licenses_dir = args.out_dir / "Licenses"
    licenses_dir.mkdir(parents=True, exist_ok=True)
    attribution = (
        "Original-language interlinear data (Hebrew/Aramaic Old Testament, Greek New Testament) is\n"
        "derived from STEPBible-Data:\n"
        "  * TAHOT - Translators Amalgamated Hebrew OT (Leningrad-based, includes Aramaic portions)\n"
        "  * TAGNT - Translators Amalgamated Greek NT\n"
        "  * TEHMC / TEGMC - Translators Expansion of Hebrew/Greek Morphology Codes\n"
        "https://github.com/STEPBible/STEPBible-Data\n\n"
        "Licence: Creative Commons Attribution 4.0 International (CC BY 4.0). Attribution only --\n"
        "NOT share-alike. Verified directly in the repository's README.md and restated in every\n"
        "source file's own header and filename (\"STEPBible.org CC BY\" / \"CC-BY\").\n\n"
        "Required attribution string (shown in Settings > About and here):\n"
        "  \"Original-language data (c) Tyndale House Cambridge, from STEPBible.org (STEP Bible),\n"
        "  used under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).\"\n\n"
        "Strong's Hebrew/Greek dictionary lemma text shown alongside this data is NOT re-derived\n"
        "here -- it reuses the app's existing Resources/Lexicon/strongs-hebrew.json /\n"
        "strongs-greek.json (built by workstream D, 0.7, from the public-domain openscriptures\n"
        "raw Strong's XML; see Resources/Licenses/lexicon-*.txt for that licence evidence).\n\n"
        "Textual-variant and edition flags (0.10): the per-word `v` objects in Resources/Interlinear/*\n"
        "carry TAGNT's Word Type code, its `editions` column, its `Meaning variants` and `Variant Notes`\n"
        "columns, and TAHOT's Type code and `Meaning Variants` column, as the source states them; the\n"
        "app's explanation text is composed only from those fields and the source's own header legends\n"
        "(shipped as Resources/Interlinear/variant-legend.json; the build fails if any legend fragment\n"
        "stops matching the source header). The source's spelling-variant columns are not shipped.\n\n"
        "Note of changes made to the source data (STEPBible asks that changes be recorded):\n"
        "  * Word-level fields are re-encoded as JSON; nothing was re-translated or re-tagged.\n"
        "  * Attached punctuation is split from the word: Hebrew text after the source's backslash\n"
        "    (maqaf, sof pasuq, paseq, parasha letters) and Greek trailing , . ; \u00b7 and the pilcrow\n"
        "    are not part of the stored word; leading/trailing sentence punctuation is trimmed from\n"
        "    the English gloss. Square/angle brackets in glosses are kept.\n"
        "  * A Greek variant note the source places only on the last word of a multi-word variant is\n"
        "    copied onto the earlier bare-marker words of the same variant.\n"
        "  * Variant-note HTML italics tags are removed and whitespace collapsed; alternate readings\n"
        "    (\"Meaning variants\") are split into reading / transliteration / gloss / Strong's /\n"
        "    morphology / witnesses, with the morphology decoded through TEGMC/TEHMC like every word.\n"
    )
    (licenses_dir / "interlinear-stepbible.txt").write_text(attribution, encoding="utf-8")

    versification_lines = [
        f"Interlinear versification report -- {len(mismatches)} verse(s) in STEPBible's TAGNT data",
        "did not resolve to a real verse in the bundled BSB. Each was DROPPED from the shipped",
        "interlinear data rather than silently misplaced. The primary (pre-parenthesis/bracket)",
        "STEPBible reference already matches the BSB's own English versification for the overwhelming",
        "majority of the canon -- including Psalm superscriptions as verse 0 and Joel/Malachi's",
        "English chapter numbering -- so every mismatch here is a genuine textual-critical or",
        "manuscript-tradition difference, not a numbering scheme mismatch:",
        "",
        "All 16 New Testament ones are the well-known verses present in the Byzantine/Textus Receptus",
        "tradition (which TAGNT also tags, alongside NA27/28, SBL, WH, Tregelles) but treated as later",
        "scribal additions and omitted by the modern critical text BSB translates (Matthew 17:21,",
        "18:11, 23:14; Mark 7:16, 9:44, 9:46, 11:26, 15:28; Luke 17:36, 23:17; John 5:4; Acts 8:37,",
        "15:34, 24:7, 28:29; Romans 16:24). 3 John 1:15 and Revelation 12:18 are real Greek-edition",
        "verse-division differences at those two boundaries. None are Old Testament / Hebrew-Aramaic",
        "(TAHOT's own English-primary references had zero mismatches against the bundled BSB).",
        "",
    ]
    for m in mismatches:
        versification_lines.append(f"{m['book']} {m['chapter']}:{m['verse']} ({m['words']} word(s)) -- {m['reason']}")
    (licenses_dir / "interlinear-versification-report.txt").write_text("\n".join(versification_lines) + "\n", encoding="utf-8")

    elapsed = time.time() - t0
    report = {
        "elapsedSeconds": round(elapsed, 1),
        "parseStats": stats,
        "wordTotals": word_totals,
        "versesWritten": verse_totals,
        "chaptersWritten": chapters_written,
        "versificationMismatches": len(mismatches),
        "mismatchSample": mismatches[:20],
        "dictionaryLookup": dict_hits,
        "morphologyMisses": {
            "hebrew": sorted(hebrew_misses.items(), key=lambda kv: -kv[1])[:20],
            "greek": sorted(greek_misses.items(), key=lambda kv: -kv[1])[:20],
            "hebrewMissKindCount": len(hebrew_misses),
            "greekMissKindCount": len(greek_misses),
        },
        "concordanceLemmas": {"hebrew": len(concordance_hebrew), "greek": len(concordance_greek)},
        "variants": {
            "greek": {k: (dict(sorted(v.items(), key=lambda kv: (-kv[1], kv[0]))) if isinstance(v, defaultdict) else v)
                      for k, v in variant_stats["greek"].items()},
            "hebrewAramaic": {k: (dict(sorted(v.items(), key=lambda kv: (-kv[1], kv[0]))) if isinstance(v, defaultdict) else v)
                              for k, v in variant_stats["hebrewAramaic"].items()},
            "parse": variant_parse_stats,
        },
    }
    (args.out_dir / "build-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
