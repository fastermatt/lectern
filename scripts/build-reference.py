#!/usr/bin/env python3
"""Builds Study Table's Passage Guide reference data (Workstream J, 0.8): Nave's Topical
Bible, Easton's Bible Dictionary, and STEPBible TIPNR people/places, plus the per-verse
reverse indexes the desk sections need. See scripts/reference-sources/SOURCES.md for exact
provenance and licence evidence for every dataset.

Raw inputs (cached, not fetched by this script) live in scripts/reference-sources/:
  Nave.zip    - official CrossWire SWORD module (DistributionLicense=Public Domain)
  Easton.zip  - official CrossWire SWORD module (DistributionLicense=Public Domain)
  TIPNR.txt   - STEPBible-Data (CC BY 4.0)

Nave's and Easton's are packed in the SWORD "zLD" binary format. There is no SWORD Python
binding available in this environment, so this script includes a small pure-Python zLD
reader (ZLDReader below), ported field-for-field from CrossWire's own reference
implementation (jsword's RawLDBackend/ZLDBackend/DataEntry, LGPL-2.1+) — see SOURCES.md.

Output is written to --out-dir (a staging directory, default a temp dir under /private/tmp)
as compact per-dataset + per-book JSON, atomic-swap-ready per the project's "generated data
is swapped in atomically" rule; the caller moves the verified staging directory into
Sources/StudyTable/Resources/Reference/ and then runs scripts/clean-sync-duplicates.sh.
Deterministic: two runs over the same inputs produce byte-identical JSON (sorted keys,
fixed separators, ensure_ascii=False).

Usage:
    python3 scripts/build-reference.py --out-dir /private/tmp/st-reference-stage
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import struct
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "scripts" / "reference-sources"
BSB_MANIFEST = ROOT / "Sources" / "StudyTable" / "Resources" / "Scripture" / "BSB" / "manifest.json"

BOOK_CODES = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI",
    "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER",
    "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP",
    "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
    "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]
BOOK_SET = set(BOOK_CODES)

REPORT: dict = {"nave": {}, "easton": {}, "tipnr": {}, "warnings": []}


def warn(msg: str) -> None:
    REPORT["warnings"].append(msg)


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")


def shard_letter(key: str) -> str:
    """Groups a detail record (a full topic/article/name, not the small per-verse index) by
    the first A-Z letter of its own key so a store only ever decodes the one shard it needs
    instead of one multi-MB file -- see the cold-load budget in ReferenceTests.swift."""
    for ch in key:
        if ch.isalpha():
            return ch.upper()
        if ch.isdigit():
            return "0-9"
    return "_"


def write_sharded(dir_path: Path, records: dict[str, object]) -> int:
    """Splits {key: value} into dir_path/<SHARD>.json files. Returns the shard count."""
    shards: dict[str, dict[str, object]] = {}
    for key, value in records.items():
        shards.setdefault(shard_letter(key), {})[key] = value
    for letter, bucket in shards.items():
        write_json(dir_path / f"{letter}.json", bucket)
    return len(shards)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Specificity ranking for the per-verse indexes (0.10, workstream R2)
# ---------------------------------------------------------------------------
#
# The 0.10 pastor QA found SIN / ROME / RIGHTEOUS on every verse of Romans 8:28-39 and GERIZIM /
# TEMPLE, SOLOMON'S on every verse of Genesis 22. Diagnosis (measured, see the build report's
# "specificity" block): a Nave's topic or Easton article that merely cites "Rom. 8" (a bare chapter --
# 27% of all Nave verse links, 18% of Easton's) or a long passage ("Rom. 2-9", "Gen. 22:1-14") was
# attached, at full weight, to EVERY verse in that span. The per-verse index recorded no notion of
# how specific a citation was, so a topic that cites a chapter as a whole looked identical to one that
# cites the verse itself, and the list was sorted alphabetically.
#
# The fix changes only the per-verse (verse -> headings) direction; the heading -> all-verses
# direction (topics/*.json refs and sections, articles) is untouched:
#   * For each (verse, heading) take the NARROWEST citing span that covers the verse.
#   * A heading whose narrowest span is <= NARROW_SPAN verses is a "direct" hit for that verse.
#   * A wider citation (a bare chapter, a section, a cross-chapter run) normally is not -- but it IS
#     kept as direct when the heading is actually NAMED in that verse's own BSB text (ABRAHAM and
#     ISAAC on Genesis 22 cite the whole story as one span, yet are plainly what verse 3 or 11 is
#     about; SIN cites "Rom. 2-9" but is named in Rom 8:3, not in 8:28). That is the only lexical
#     signal used: whole-word, case-insensitive match of the heading's lead phrase, simple plural
#     tolerance, nothing fuzzy.
#   * Direct hits are ranked narrow-cited first, then narrowest span, then by how few references the
#     whole heading has (a heading that cites little is more distinctive for the verses it does cite
#     than a giant topic like GOD or SIN), then by name; the first *_PRIMARY_CAP go in `verse-index/`
#     (what the desk shows). Direct overflow and every remaining wider-passage hit go, ranked the
#     same way, in `verse-index-more/` (what the desk offers behind a "N more" control). Nothing is
#     dropped: every heading that ever attached to a verse still does, in one file or the other.
NARROW_SPAN = 10
NAVE_PRIMARY_CAP = 12
EASTON_PRIMARY_CAP = 8


def _lead_phrase_pattern(heading: str) -> re.Pattern | None:
    """Whole-word, case-insensitive pattern for a heading's lead phrase ("JESUS, THE CHRIST" ->
    Jesus; "WICKED (PEOPLE)" -> wicked; "TEMPLE, SOLOMON'S" -> temple), tolerating a plural / possessive /
    -ed / -ing ending. None for phrases too short to match responsibly."""
    lead = re.split(r"[,(]", heading, maxsplit=1)[0].strip()
    words = re.findall(r"[A-Za-z]+", lead)
    if not words or len(lead) < 4:
        return None
    last = words[-1]
    stem = last[:-1] if last.lower().endswith("s") and len(last) > 4 else last
    body = r"\s+".join(re.escape(w) for w in words[:-1] + [stem])
    return re.compile(rf"\b{body}(?:s|es|'s|\u2019s|ed|ing)?\b", re.IGNORECASE)


_PATTERNS: dict[str, re.Pattern | None] = {}


def named_in_text(heading: str, text: str) -> bool:
    if heading not in _PATTERNS:
        _PATTERNS[heading] = _lead_phrase_pattern(heading)
    pattern = _PATTERNS[heading]
    return bool(pattern and pattern.search(text))


def rank_headings(widths: dict[str, int], sizes: dict[str, int], cap: int,
                  verse_text: str = "") -> tuple[list[str], list[str]]:
    """widths: heading -> narrowest citing span (verses) covering this verse. -> (primary, more)."""
    direct: list[tuple[int, int, int, str]] = []
    wider: list[tuple[int, int, str]] = []
    for heading, width in widths.items():
        if width <= NARROW_SPAN:
            direct.append((0, width, sizes.get(heading, 0), heading))
        elif verse_text and named_in_text(heading, verse_text):
            direct.append((1, width, sizes.get(heading, 0), heading))
        else:
            wider.append((width, sizes.get(heading, 0), heading))
    direct.sort()
    wider.sort()
    ordered_direct = [h for _, _, _, h in direct]
    return ordered_direct[:cap], ordered_direct[cap:] + [h for _, _, h in wider]


def write_ranked_indexes(out_dir: Path, dataset: str, widths_by_book: dict[str, dict[str, dict[str, int]]],
                         sizes: dict[str, int], cap: int) -> dict:
    """Writes <dataset>/verse-index/<BOOK>.json (primary) and <dataset>/verse-index-more/<BOOK>.json
    (the rest); returns the before/after statistics for the build report."""
    before_counts: list[int] = []
    primary_counts: list[int] = []
    verses_without_primary = 0
    links = primary_links = more_links = 0
    for code in BOOK_CODES:
        primary_index: dict[str, list[str]] = {}
        more_index: dict[str, list[str]] = {}
        book_text = load_bsb_book_text(code) if widths_by_book[code] else {}
        for key, widths in widths_by_book[code].items():
            chapter_text, verse_text = key.split(":")
            primary, more = rank_headings(
                widths, sizes, cap, book_text.get(int(chapter_text), {}).get(int(verse_text), ""))
            links += len(widths)
            primary_links += len(primary)
            more_links += len(more)
            before_counts.append(len(widths))
            primary_counts.append(len(primary))
            if primary:
                primary_index[key] = primary
            else:
                verses_without_primary += 1
            if more:
                more_index[key] = more
        if primary_index:
            write_json(out_dir / dataset / "verse-index" / f"{code}.json", primary_index)
        if more_index:
            write_json(out_dir / dataset / "verse-index-more" / f"{code}.json", more_index)

    def spread(counts: list[int]) -> dict:
        ordered = sorted(counts)
        n = len(ordered)
        return {"mean": round(sum(ordered) / n, 2), "median": ordered[n // 2],
                "p95": ordered[int(n * 0.95)], "max": ordered[-1]} if n else {}

    return {
        "versesIndexed": len(before_counts),
        "linksBefore(allHeadingsPerVerse)": links,
        "linksNowPrimary": primary_links,
        "linksNowBehindMore": more_links,
        "percentLinksMovedBehindMore": round(100 * more_links / links, 1) if links else 0,
        "headingsPerVerseBefore": spread(before_counts),
        "headingsPerVerseNowShown": spread(primary_counts),
        "versesWithNoDirectHeading": verses_without_primary,
        "narrowSpanVerses": NARROW_SPAN,
        "primaryCap": cap,
    }


# ---------------------------------------------------------------------------
# Chapter/verse counts (BSB versification is this app's canonical reference)
# ---------------------------------------------------------------------------

def load_verse_counts() -> dict[str, list[int]]:
    manifest = json.loads(BSB_MANIFEST.read_text(encoding="utf-8"))
    return {b["code"]: b["verses"] for b in manifest["books"]}


VERSE_COUNTS = load_verse_counts()
BSB_BOOKS_DIR = BSB_MANIFEST.parent


def load_bsb_book_text(code: str) -> dict[int, dict[int, str]]:
    """chapter -> verse -> BSB text, for the one book. Used only to bridge a documented
    TIPNR/ESV-vs-BSB wording gap (see build_tipnr's same-chapter enrichment pass)."""
    path = BSB_BOOKS_DIR / f"{code}.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    out: dict[int, dict[int, str]] = {}
    for chapter in data.get("chapters", []):
        out[chapter["n"]] = {v: t for v, t in zip(chapter["v"], chapter["t"]) if v > 0}
    return out


def verse_count(code: str, chapter: int) -> int:
    counts = VERSE_COUNTS.get(code)
    if not counts or chapter < 1 or chapter > len(counts):
        return 0
    return counts[chapter - 1]


def clamp_ref(code: str, chapter: int, verse: int) -> tuple[int, int] | None:
    """Clamps a chapter/verse pair to the bundled BSB canon, reporting the mismatch once.
    Returns None only when the book itself has no bundled chapter count at all."""
    counts = VERSE_COUNTS.get(code)
    if not counts:
        return None
    chapter = min(max(chapter, 1), len(counts))
    last = counts[chapter - 1]
    if verse > last:
        verse = last
    return (chapter, max(verse, 1))


def split_range(code: str, start_chapter: int, start_verse: int, end_chapter: int, end_verse: int):
    """Splits a (possibly cross-chapter) reference range into one {code,chapter,start,end}
    dict per chapter, clamped to the bundled BSB canon. Matches the CrossReference /
    StandardProof convention already used elsewhere in this app (single chapter per ref)."""
    if code not in BOOK_SET:
        return []
    sc = clamp_ref(code, start_chapter, start_verse)
    ec = clamp_ref(code, end_chapter, end_verse)
    if sc is None or ec is None:
        return []
    (start_chapter, start_verse), (end_chapter, end_verse) = sc, ec
    if end_chapter < start_chapter:
        end_chapter = start_chapter
    out = []
    for ch in range(start_chapter, end_chapter + 1):
        v_start = start_verse if ch == start_chapter else 1
        v_end = end_verse if ch == end_chapter else verse_count(code, ch)
        if v_end <= 0:
            v_end = v_start
        if v_end < v_start:
            v_start, v_end = v_end, v_start
        out.append({"code": code, "chapter": ch, "start": v_start, "end": v_end})
    return out


# ---------------------------------------------------------------------------
# zLD reader (SWORD compressed local dictionary) -- see SOURCES.md for provenance.
# ---------------------------------------------------------------------------

def _u32(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0]


def _i32(b: bytes, off: int) -> int:
    return struct.unpack_from("<i", b, off)[0]


class ZLDReader:
    def __init__(self, idx: bytes, dat: bytes, zdx: bytes, zdt: bytes):
        self.idx, self.dat, self.zdx, self.zdt = idx, dat, zdx, zdt
        self._blocks: dict[int, bytes] = {}

    @property
    def cardinality(self) -> int:
        return len(self.idx) // 8

    def _block(self, block_num: int) -> bytes:
        cached = self._blocks.get(block_num)
        if cached is not None:
            return cached
        off = block_num * 8
        start = _u32(self.zdx, off)
        size = _i32(self.zdx, off + 4)
        uncompressed = zlib.decompress(self.zdt[start:start + size])
        self._blocks[block_num] = uncompressed
        return uncompressed

    def entries(self):
        for i in range(self.cardinality):
            idx_off = i * 8
            dat_offset = _u32(self.idx, idx_off)
            dat_size = _i32(self.idx, idx_off + 4)
            if dat_size <= 0:
                continue
            record = self.dat[dat_offset:dat_offset + dat_size]
            key_end = record.find(b"\n")
            if key_end < 0:
                continue
            key_bytes = record[:key_end]
            if key_bytes.endswith(b"\r"):
                key_bytes = key_bytes[:-1]
            if key_bytes.endswith(b"\\"):
                key_bytes = key_bytes[:-1]
            key = key_bytes.decode("utf-8", errors="replace")

            field_start = key_end + 1
            if field_start + 8 > len(record):
                continue
            block_num = _u32(record, field_start)
            block_entry = _i32(record, field_start + 4)

            block = self._block(block_num)
            entry_count = _u32(block, 0)
            if block_entry < 0 or block_entry >= entry_count:
                yield key, ""
                continue
            table_off = 4 + 8 * block_entry
            entry_start = _u32(block, table_off)
            entry_size = _u32(block, table_off + 4)
            raw = block[entry_start:entry_start + entry_size]
            if raw.endswith(b"\x00"):
                raw = raw[:-1]
            yield key, raw.decode("utf-8", errors="replace").strip()


def open_zld_module(zip_path: Path, base: str) -> ZLDReader:
    """`base` is the DataPath's final path component from the module's .conf, e.g. 'dict'
    for Nave or 'easton' for Easton's, inside modules/lexdict/zld/<initials>/."""
    with zipfile.ZipFile(zip_path) as zf:
        names = {Path(n).name: n for n in zf.namelist()}

        def read(suffix: str) -> bytes:
            wanted = f"{base}{suffix}"
            if wanted not in names:
                raise KeyError(f"{wanted} not found in {zip_path} (have: {sorted(names)})")
            return zf.read(names[wanted])

        return ZLDReader(read(".idx"), read(".dat"), read(".zdx"), read(".zdt"))


# ---------------------------------------------------------------------------
# TEI markup -> plain text / structured refs
# ---------------------------------------------------------------------------

REF_TAG = re.compile(r'<ref\s+(?:osisRef|target)="([^"]*)"[^>]*>(.*?)</ref>', re.S)
TAG = re.compile(r"<[^>]+>")
OSIS_BOOK = re.compile(r"^(?:Bible:)?([1-3]?[A-Za-z]+)\.(\d+)(?:\.(\d+))?(?:-(?:Bible:)?([1-3]?[A-Za-z]+)\.(\d+)\.(\d+))?$")

OSIS_TO_USFM = {
    "Gen": "GEN", "Exod": "EXO", "Lev": "LEV", "Num": "NUM", "Deut": "DEU", "Josh": "JOS",
    "Judg": "JDG", "Ruth": "RUT", "1Sam": "1SA", "2Sam": "2SA", "1Kgs": "1KI", "2Kgs": "2KI",
    "1Chr": "1CH", "2Chr": "2CH", "Ezra": "EZR", "Neh": "NEH", "Esth": "EST", "Job": "JOB",
    "Ps": "PSA", "Prov": "PRO", "Eccl": "ECC", "Song": "SNG", "Isa": "ISA", "Jer": "JER",
    "Lam": "LAM", "Ezek": "EZK", "Dan": "DAN", "Hos": "HOS", "Joel": "JOL", "Amos": "AMO",
    "Obad": "OBA", "Jonah": "JON", "Mic": "MIC", "Nah": "NAM", "Hab": "HAB", "Zeph": "ZEP",
    "Hag": "HAG", "Zech": "ZEC", "Mal": "MAL", "Matt": "MAT", "Mark": "MRK", "Luke": "LUK",
    "John": "JHN", "Acts": "ACT", "Rom": "ROM", "1Cor": "1CO", "2Cor": "2CO", "Gal": "GAL",
    "Eph": "EPH", "Phil": "PHP", "Col": "COL", "1Thess": "1TH", "2Thess": "2TH", "1Tim": "1TI",
    "2Tim": "2TI", "Titus": "TIT", "Phlm": "PHM", "Heb": "HEB", "Jas": "JAS", "1Pet": "1PE",
    "2Pet": "2PE", "1John": "1JN", "2John": "2JN", "3John": "3JN", "Jude": "JUD", "Rev": "REV",
}
OSIS_APOCRYPHA = {"1Macc", "2Macc", "3Macc", "4Macc", "PrAzar", "Wis", "Sir", "Tob", "Jdt",
                   "Bar", "EpJer", "1Esd", "2Esd", "PrMan", "AddEsth", "SusOG", "SusTh",
                   "BelOG", "BelTh"}


def parse_osis_ref(raw: str) -> list[dict]:
    """One osisRef attribute (single verse, single-book range, or verse-list token) into
    zero or more {code,chapter,start,end} dicts, split per chapter."""
    raw = raw.strip()
    m = OSIS_BOOK.match(raw)
    if not m:
        return []
    b1, c1, v1, b2, c2, v2 = m.groups()
    if b1 in OSIS_APOCRYPHA or (b2 and b2 in OSIS_APOCRYPHA):
        return []
    code1 = OSIS_TO_USFM.get(b1)
    if not code1:
        return []
    chapter1 = int(c1)
    verse1 = int(v1) if v1 else 1
    if b2 is None:
        # A bare "Gen.1" (whole-chapter ref, no verse) -> span the whole chapter.
        if v1 is None:
            return split_range(code1, chapter1, 1, chapter1, verse_count(code1, chapter1) or 1)
        return split_range(code1, chapter1, verse1, chapter1, verse1)
    code2 = OSIS_TO_USFM.get(b2)
    if not code2 or code2 != code1:
        # Cross-book ranges are not expected from these sources; take the start point only.
        return split_range(code1, chapter1, verse1, chapter1, verse1)
    return split_range(code1, chapter1, verse1, int(c2), int(v2))


def strip_tags(text: str) -> str:
    return html.unescape(TAG.sub("", text)).strip()


def clean_easton_body(tei: str) -> tuple[str, str]:
    """Returns (title, plain-text body) for one Easton TEI entry."""
    title_m = re.search(r"<title>(.*?)</title>", tei, re.S)
    title = strip_tags(title_m.group(1)) if title_m else ""
    body = tei
    if title_m:
        body = body[:title_m.start()] + body[title_m.end():]
    body = re.sub(r"</?entryFree[^>]*>", "", body)
    # Turn <ref ...>text</ref> into just its visible text (refs are re-derived structurally
    # below, not needed inline in the reading text).
    body = REF_TAG.sub(lambda m: strip_tags(m.group(2)), body)
    paragraphs = re.findall(r"<p>(.*?)</p>", body, re.S)
    if not paragraphs:
        paragraphs = [body]
    cleaned = [strip_tags(p) for p in paragraphs]
    return title, "\n\n".join(p for p in cleaned if p)


def nave_refs_and_links(tei: str) -> tuple[list[dict], list[str], list[dict]]:
    """Returns (all verse refs, seeAlso topic names, sections) for one Nave's entry.
    Sections group refs under the entry's own '→ HEADING' sub-labels where present."""
    body = re.sub(r"</?entryFree[^>]*>|</?def>|</?list>|</?item>", "", tei)
    lines = body.split("<lb/>")
    all_refs: list[dict] = []
    see_also: list[str] = []
    sections: list[dict] = []
    current_heading = ""
    current_refs: list[dict] = []

    def flush():
        if current_refs:
            sections.append({"heading": current_heading, "refs": list(current_refs)})

    for line in lines:
        line_refs: list[dict] = []
        for m in re.finditer(r'<ref\s+osisRef="([^"]*)"[^>]*>.*?</ref>', line):
            for r in parse_osis_ref(m.group(1)):
                line_refs.append(r)
                all_refs.append(r)
        for m in re.finditer(r'<ref\s+target="Nave:([^"]*)"[^>]*>.*?</ref>', line):
            see_also.append(m.group(1).strip())
        text_only = strip_tags(re.sub(r"<ref\b[^>]*>.*?</ref>", "", line, flags=re.S))
        arrow_split = text_only.split("→", 1)
        heading_candidate = arrow_split[1].strip() if len(arrow_split) > 1 else ""
        if heading_candidate:
            flush()
            current_heading = heading_candidate
            current_refs = list(line_refs)
        else:
            current_refs.extend(line_refs)
    flush()

    # Dedup while preserving order.
    seen = set()
    deduped_refs = []
    for r in all_refs:
        key = (r["code"], r["chapter"], r["start"], r["end"])
        if key not in seen:
            seen.add(key)
            deduped_refs.append(r)
    seen_topics = set()
    deduped_topics = []
    for t in see_also:
        if t not in seen_topics:
            seen_topics.add(t)
            deduped_topics.append(t)
    return deduped_refs, deduped_topics, sections


# ---------------------------------------------------------------------------
# Nave's Topical Bible
# ---------------------------------------------------------------------------

def build_nave(out_dir: Path) -> tuple[dict, dict[str, dict[str, dict[str, int]]]]:
    """Returns (summary, verse -> topic -> narrowest citing span) -- the latter feeds Easton's
    topic-derived links so a wide Nave citation cannot re-enter Easton at full weight."""
    reader = open_zld_module(SOURCES / "Nave.zip", "dict")
    topics: dict[str, dict] = {}
    widths_by_book: dict[str, dict[str, dict[str, int]]] = {code: {} for code in BOOK_CODES}
    total_refs = 0
    for key, text in reader.entries():
        if not text:
            continue
        refs, see_also, sections = nave_refs_and_links(text)
        if not refs and not see_also:
            continue
        topics[key] = {"refs": refs, "seeAlso": see_also, "sections": sections}
        total_refs += len(refs)
        for r in refs:
            width = r["end"] - r["start"] + 1
            for v in range(r["start"], r["end"] + 1):
                bucket = widths_by_book[r["code"]].setdefault(f"{r['chapter']}:{v}", {})
                if key not in bucket or width < bucket[key]:
                    bucket[key] = width

    write_sharded(out_dir / "nave" / "topics", topics)
    sizes = {key: len(topic["refs"]) for key, topic in topics.items()}
    specificity = write_ranked_indexes(out_dir, "nave", widths_by_book, sizes, NAVE_PRIMARY_CAP)
    REPORT["nave-specificity"] = specificity

    john_3_16 = widths_by_book["JHN"].get("3:16", {})
    return {
        "topicCount": len(topics),
        "totalRefs": total_refs,
        "booksWithCoverage": sum(1 for c in BOOK_CODES if widths_by_book[c]),
        "john3-16Topics": sorted(john_3_16),
    }, widths_by_book


# ---------------------------------------------------------------------------
# Easton's Bible Dictionary
# ---------------------------------------------------------------------------

EASTON_BOOK_INTROS = {
    "GEN": "GENESIS", "EXO": "EXODUS, BOOK OF", "LEV": "LEVITICUS", "NUM": "NUMBERS, BOOK OF",
    "DEU": "DEUTERONOMY", "JOS": "JOSHUA, THE BOOK OF", "JDG": "JUDGES, BOOK OF",
    "RUT": "RUTH THE BOOK OF", "1SA": "SAMUEL, BOOKS OF", "2SA": "SAMUEL, BOOKS OF",
    "1KI": "KINGS, THE BOOKS OF", "2KI": "KINGS, THE BOOKS OF",
    "1CH": "CHRONICLES, BOOKS OF", "2CH": "CHRONICLES, BOOKS OF", "EZR": "EZRA, BOOK OF",
    "NEH": "NEHEMIAH, BOOK OF", "EST": "ESTHER, BOOK OF", "JOB": "JOB, BOOK OF",
    "PSA": "PSALMS", "PRO": "PROVERBS, BOOK OF", "ECC": "ECCLESIASTES", "SNG": "SONGS",
    "ISA": "ISAIAH, THE BOOK OF", "JER": "JEREMIAH, BOOK OF", "LAM": "LAMENTATIONS, BOOK OF",
    "EZK": "EZEKIEL, BOOK OF", "DAN": "DANIEL, BOOK OF", "HOS": "HOSEA, PROPHECIES OF",
    "JOL": "JOEL, BOOK OF", "AMO": "AMOS", "OBA": "OBADIAH, BOOK OF", "JON": "JONAH, BOOK OF",
    "MIC": "MICAH, BOOK OF", "NAM": "NAHUM, BOOK OF", "HAB": "HABAKKUK, PROPHECIES OF",
    "ZEP": "ZEPHANIAH", "HAG": "HAGGAI, BOOK OF", "ZEC": "ZECHARIAH",
    "MAL": "MALACHI, PROPHECIES OF", "MAT": "MATTHEW, GOSPEL ACCORDING TO",
    "MRK": "MARK, GOSPEL ACCORDING TO", "LUK": "LUKE, GOSPEL ACCORDING TO",
    "JHN": "JOHN, GOSPEL OF", "ACT": "ACTS OF THE APOSTLES", "ROM": "ROMANS, EPISTLE TO THE",
    "1CO": "CORINTHIANS, FIRST EPISTLE TO THE", "2CO": "CORINTHIANS, SECOND EPISTLE TO THE",
    "GAL": "GALATIANS, EPISTLE TO", "EPH": "EPHESIANS, EPISTLE TO",
    "PHP": "PHILIPPIANS, EPISTLE TO", "COL": "COLOSSIANS, EPISTLE TO THE",
    "1TH": "THESSALONIANS, EPISTLES TO THE", "2TH": "THESSALONIANS, EPISTLES TO THE",
    "1TI": "TIMOTHY, FIRST EPISTLE TO", "2TI": "TIMOTHY, SECOND EPISTLE TO",
    "TIT": "TITUS, EPISTLE TO", "PHM": "PHILEMON, EPISTLE TO", "HEB": "HEBREWS, EPISTLE TO",
    "JAS": "JAMES, EPISTLE OF", "1PE": "PETER, FIRST EPISTLE OF",
    "2PE": "PETER, SECOND EPISTLE OF", "1JN": "JOHN, FIRST EPISTLE OF",
    "2JN": "JOHN, SECOND EPISTLE OF", "3JN": "JOHN, THIRD EPISTLE OF",
    "JUD": "JUDE, EPISTLE OF", "REV": "REVELATION, BOOK OF",
}


def build_easton(out_dir: Path, nave_widths: dict[str, dict[str, dict[str, int]]]) -> dict:
    reader = open_zld_module(SOURCES / "Easton.zip", "easton")
    articles: dict[str, dict] = {}
    article_refs: dict[str, list[dict]] = {}
    for key, text in reader.entries():
        if not text:
            continue
        title, body = clean_easton_body(text)
        if not body:
            continue
        headword = key.upper()
        articles[headword] = {"title": title or key, "text": body}
        refs: list[dict] = []
        for m in re.finditer(r'<ref\s+osisRef="([^"]*)"[^>]*>.*?</ref>', text):
            refs.extend(parse_osis_ref(m.group(1)))
        article_refs[headword] = refs

    missing_intros = [code for code, headword in EASTON_BOOK_INTROS.items() if headword not in articles]
    for code in missing_intros:
        warn(f"Easton book intro missing for {code}: {EASTON_BOOK_INTROS[code]!r} not found")
    book_intros = {code: headword for code, headword in EASTON_BOOK_INTROS.items() if headword in articles}

    # verse -> headwords, from (a) the article's own cited references, and (b) any Nave's
    # topic already resolved for that verse whose name exactly matches an Easton headword
    # (per WORKPLAN J.2: "articles linked from the verse ... and from Topics"). Each link carries the
    # narrowest citing span (own reference, or the Nave topic's own narrowest span for that verse),
    # exactly as build_nave() does -- see the "Specificity ranking" comment above.
    widths_by_book: dict[str, dict[str, dict[str, int]]] = {code: {} for code in BOOK_CODES}
    from_refs = 0
    for headword, refs in article_refs.items():
        for r in refs:
            width = r["end"] - r["start"] + 1
            for v in range(r["start"], r["end"] + 1):
                bucket = widths_by_book[r["code"]].setdefault(f"{r['chapter']}:{v}", {})
                if headword not in bucket:
                    from_refs += 1
                if headword not in bucket or width < bucket[headword]:
                    bucket[headword] = width

    from_topics = 0
    for code in BOOK_CODES:
        for verse_key, topic_widths in nave_widths[code].items():
            for topic, width in topic_widths.items():
                if topic in articles:
                    bucket = widths_by_book[code].setdefault(verse_key, {})
                    if topic not in bucket:
                        from_topics += 1
                    if topic not in bucket or width < bucket[topic]:
                        bucket[topic] = width

    write_sharded(out_dir / "easton" / "articles", articles)
    write_json(out_dir / "easton" / "book-intros.json", book_intros)
    sizes = {headword: len(refs) for headword, refs in article_refs.items()}
    REPORT["easton-specificity"] = write_ranked_indexes(out_dir, "easton", widths_by_book, sizes, EASTON_PRIMARY_CAP)

    return {
        "articleCount": len(articles),
        "bookIntros": len(book_intros),
        "missingBookIntros": missing_intros,
        "linksFromArticleRefs": from_refs,
        "linksFromTopics": from_topics,
        "booksWithCoverage": sum(1 for c in BOOK_CODES if widths_by_book[c]),
        "genesis1-1Links": sorted(widths_by_book["GEN"].get("1:1", {})),
    }


# ---------------------------------------------------------------------------
# STEPBible TIPNR (people & places)
# ---------------------------------------------------------------------------

TIPNR_BOOK_ALIASES = {
    "deut": "DEU", "dt": "DEU", "ezra": "EZR", "josh": "JOS", "psalm": "PSA", "psalms": "PSA",
    "jam": "JAS",
}
TIPNR_IGNORE_TOKENS = {"etc", "lxx", "id", "1cl"}
TIPNR_REF_TOKEN = re.compile(r"^([1-3]?[A-Za-z]+)\.(\d+)\.(\d+)")


def tipnr_book_code(token: str) -> str | None:
    lower = token.lower()
    if lower in TIPNR_IGNORE_TOKENS:
        return None
    if lower in TIPNR_BOOK_ALIASES:
        return TIPNR_BOOK_ALIASES[lower]
    upper = token.upper()
    return upper if upper in BOOK_SET else None


def parse_tipnr_refs(field: str) -> list[tuple[str, int, int]]:
    out = []
    for token in field.split(";"):
        token = token.strip()
        if not token:
            continue
        token = re.sub(r"\(\??[a-z]?\)$", "", token).strip()
        m = TIPNR_REF_TOKEN.match(token)
        if not m:
            continue
        code = tipnr_book_code(m.group(1))
        if not code:
            continue
        chapter, verse = int(m.group(2)), int(m.group(3))
        clamped = clamp_ref(code, chapter, verse)
        if clamped:
            out.append((code, clamped[0], clamped[1]))
    return out


def parse_tipnr(text: str) -> dict[str, dict]:
    lines = text.split("\n")
    markers = [i for i, l in enumerate(lines) if l.startswith("$==")]
    records: dict[str, dict] = {}
    skipped_excluded = 0
    for idx, start in enumerate(markers):
        end = markers[idx + 1] if idx + 1 < len(markers) else len(lines)
        header = lines[start]
        category = header.lstrip("$= \t")
        category_norm = re.sub(r"\s+", " ", category).strip().upper()
        if category_norm.startswith("EXCLUDED"):
            skipped_excluded += 1
            continue
        block = lines[start + 1:end]
        if not block:
            continue
        main = block[0].split("\t")
        if not main or main[0].startswith("UnifiedName=") or main[0].startswith("UniqueName="):
            continue  # a repeated column-header row, not a real record
        raw_id = main[0]
        if "=" not in raw_id or "@" not in raw_id:
            continue
        name_and_ref = raw_id.rsplit("=", 1)[0]
        display_name = name_and_ref.split("@", 1)[0].strip()
        if not display_name:
            continue
        kind = "person" if category_norm.startswith("PERSON") else (
            "place" if category_norm.startswith("PLACE") else "other")

        refs: set[tuple[str, int, int]] = set()
        name_variants: set[str] = {display_name}
        briefest = brief = short = ""
        for line in block[1:]:
            if line.startswith("– Total") or line.startswith("- Total"):
                continue
            if line.startswith("–") or line.startswith("-"):
                cols = line.split("\t")
                if len(cols) > 4:
                    refs.update(parse_tipnr_refs(cols[4]))
                if len(cols) > 3:
                    # "Paul" or "Paul =KJV,TR; [ ] =ESV,NIV,NA" -- one candidate spelling
                    # per translation, semicolon-joined; "[ ]" means that group of
                    # translations renders it as a pronoun (nothing to match against).
                    for variant in cols[3].split(";"):
                        candidate = variant.split("=", 1)[0].strip()
                        if candidate and candidate != "[ ]" and candidate[0].isupper():
                            name_variants.add(candidate)
            elif line.startswith("@Briefest="):
                briefest = line[len("@Briefest="):].strip()
            elif line.startswith("@Brief="):
                brief = line.split("\t")[0][len("@Brief="):].strip()
            elif line.startswith("@Short="):
                short = line.split("\t")[0][len("@Short="):].strip()

        description = short or brief or briefest
        if not description or not refs:
            continue
        record_id = name_and_ref
        records[record_id] = {
            "name": display_name,
            "kind": kind,
            "description": description,
            "refs": refs,  # a set; sorted once by the caller after any enrichment pass
            "nameVariants": sorted(name_variants),
        }
    REPORT["tipnr"]["excludedCategorySkipped"] = skipped_excluded
    return records


def enrich_same_chapter_name_matches(records: dict[str, dict]) -> int:
    """TIPNR tags name occurrences against its own base text (mainly the ESV, per its own
    header: "Proper Nouns in the ESV (+ differences in KJV & NIV)"); the BSB (this app's
    base text) sometimes names a person explicitly where the ESV uses a pronoun instead --
    e.g. Acts 9:3 BSB reads "As Saul drew near to Damascus..." while the ESV has "Now as he
    went on his way...", so TIPNR's own reference list for the apostle Paul/Saul jumps from
    Act.7.58 to Act.9.4 and never tags verse 3. Documented in SOURCES.md.

    Bounded, same-chapter, whole-word enrichment: for every chapter where a record already
    has at least one TIPNR-confirmed occurrence, also tag any other verse in that SAME
    chapter where the record's own display name appears as a whole word in the BSB text.
    Bounding to a chapter TIPNR itself already ties to this specific individual keeps two
    unrelated people who happen to share a bare first name (there are two different "Saul"s
    in the Bible) from being conflated project-wide."""
    book_cache: dict[str, dict[int, dict[int, str]]] = {}
    pattern_cache: dict[str, re.Pattern] = {}
    added = 0
    for r in records.values():
        chapters_by_book: dict[str, set[int]] = {}
        for code, chapter, _ in r["refs"]:
            chapters_by_book.setdefault(code, set()).add(chapter)
        if not chapters_by_book:
            continue
        variants = [v for v in r.get("nameVariants", [r["name"]]) if v and len(v) >= 3]
        if not variants:
            continue
        patterns = []
        for v in variants:
            pattern = pattern_cache.get(v)
            if pattern is None:
                pattern = re.compile(r"\b" + re.escape(v) + r"\b")
                pattern_cache[v] = pattern
            patterns.append(pattern)
        for code, chapters in chapters_by_book.items():
            book_text = book_cache.setdefault(code, load_bsb_book_text(code))
            for chapter in chapters:
                for verse, text in book_text.get(chapter, {}).items():
                    key = (code, chapter, verse)
                    if key not in r["refs"] and any(p.search(text) for p in patterns):
                        r["refs"].add(key)
                        added += 1
    return added


def build_tipnr(out_dir: Path) -> dict:
    text = (SOURCES / "TIPNR.txt").read_text(encoding="utf-8", errors="replace")
    records = parse_tipnr(text)
    added = enrich_same_chapter_name_matches(records)
    REPORT["tipnr"]["sameChapterBsbEnrichments"] = added
    names_out = {rid: {"name": r["name"], "kind": r["kind"], "description": r["description"],
                        "refs": [{"code": c, "chapter": ch, "verse": v} for c, ch, v in sorted(r["refs"])]}
                 for rid, r in records.items()}
    verse_index: dict[str, dict[str, list[str]]] = {code: {} for code in BOOK_CODES}
    for rid, r in records.items():
        for code, chapter, verse in r["refs"]:
            bucket = verse_index[code].setdefault(f"{chapter}:{verse}", [])
            if rid not in bucket:
                bucket.append(rid)

    write_sharded(out_dir / "tipnr" / "names", names_out)
    for code in BOOK_CODES:
        if verse_index[code]:
            write_json(out_dir / "tipnr" / "verse-index" / f"{code}.json", verse_index[code])

    acts_9_3 = verse_index["ACT"].get("9:3", [])
    acts_9_3_names = sorted({names_out[rid]["name"] for rid in acts_9_3})
    return {
        "nameCount": len(records),
        "personCount": sum(1 for r in records.values() if r["kind"] == "person"),
        "placeCount": sum(1 for r in records.values() if r["kind"] == "place"),
        "otherCount": sum(1 for r in records.values() if r["kind"] == "other"),
        "booksWithCoverage": sum(1 for c in BOOK_CODES if verse_index[c]),
        "acts9-3Names": acts_9_3_names,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="/private/tmp/st-reference-stage")
    args = parser.parse_args()
    out_dir = Path(args.out_dir)
    if out_dir.exists():
        import shutil
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    nave_summary, nave_widths = build_nave(out_dir)
    REPORT["nave"] = nave_summary
    REPORT["easton"] = build_easton(out_dir, nave_widths)
    tipnr_summary = build_tipnr(out_dir)
    REPORT["tipnr"] = {**REPORT.get("tipnr", {}), **tipnr_summary}

    meta = {
        "schema": 1,
        "attribution": {
            "nave": "Nave's Topical Bible (1896, Orville J. Nave) — Public Domain. "
                     "Digital text: CrossWire SWORD project (crosswire.org), sourced from CCEL.",
            "easton": "Easton's Bible Dictionary (1897, M.G. Easton) — Public Domain. "
                       "Digital text: CrossWire SWORD project (crosswire.org), sourced from CCEL.",
            "tipnr": "Proper names data from TIPNR, STEPBible.org (CC BY 4.0), Tyndale House "
                      "Cambridge. Person/place descriptions are STEPBible's own AI-drafted "
                      "summaries, published by STEPBible under the same licence.",
        },
        "sourceHashes": {
            "Nave.zip": sha256(SOURCES / "Nave.zip"),
            "Easton.zip": sha256(SOURCES / "Easton.zip"),
            "TIPNR.txt": sha256(SOURCES / "TIPNR.txt"),
        },
    }
    write_json(out_dir / "meta.json", meta)

    print(json.dumps(REPORT, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
