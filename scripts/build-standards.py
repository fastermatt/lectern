#!/usr/bin/env python3
"""Builds Resources/Confession/standards/*.json and the proof-text reverse index for
Workstream B (Confessional standards & proof texts).

Deterministic: every run on the same raw-sources/ inputs produces byte-identical output.
Raw inputs live in scripts/standards-sources/raw/ (fetched once, committed for
reproducibility — see scripts/standards-sources/SOURCES.md for provenance/licence notes
per document). This script only *parses* those cached files; it does not fetch anything.

Documents built:
  wcf  - Westminster Confession of Faith (American revision structure; historic 1647
         Assembly proof texts wherever the American wording is substantially unchanged)
  wlc  - Westminster Larger Catechism (1647 Assembly text + proofs)
  wsc  - Westminster Shorter Catechism (1647 Assembly text; proofs from the traditional
         annexed Scripture-proof apparatus)
  hc   - Heidelberg Catechism (traditional public-domain English translation + its
         lettered proof-text apparatus)
  bc   - Belgic Confession (Schaff's Creeds of Christendom vol. 3, 1877/1889, explicitly
         public domain; RCA-authorized English translation with footnoted proofs)
  cd   - Canons of Dort (positive articles + Rejection of Errors, with inline Scripture
         citations as its historic proof-text apparatus)

Usage: python3 scripts/build-standards.py [--report-only]
"""
import json
import os
import re
import sys
import hashlib
import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "scripts" / "standards-sources" / "raw"
OUT_DIR = ROOT / "Sources" / "StudyTable" / "Resources" / "Confession" / "standards"
BSB_MANIFEST = ROOT / "Sources" / "StudyTable" / "Resources" / "Scripture" / "BSB" / "manifest.json"

REPORT = {"documents": {}, "warnings": []}

# ---------------------------------------------------------------------------
# Canon and reference parsing
# ---------------------------------------------------------------------------

BOOK_CODES = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI",
    "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER",
    "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP",
    "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
    "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
    "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]

# Every alias we encounter across the raw sources (OSIS-ish English abbreviations from
# nlf/CCEL, classic English abbreviations from thewestminsterstandard.org, and the French
# abbreviations Schaff's Belgic Confession footnotes use) -> USFM code. Lowercased,
# punctuation-stripped keys.
_ALIAS_PAIRS = [
    ("gen", "GEN"), ("genesis", "GEN"),
    ("exo", "EXO"), ("exod", "EXO"), ("exodus", "EXO"), ("ex", "EXO"),
    ("lev", "LEV"), ("leviticus", "LEV"),
    ("num", "NUM"), ("numbers", "NUM"),
    ("deu", "DEU"), ("deut", "DEU"), ("deuteronomy", "DEU"),
    ("denteronomy", "DEU"),  # verbatim OCR typo present in the CCEL Heidelberg Catechism source (Q. 92)
    ("jos", "JOS"), ("josh", "JOS"), ("joshua", "JOS"),
    ("jdg", "JDG"), ("judg", "JDG"), ("judges", "JDG"),
    ("rut", "RUT"), ("ruth", "RUT"),
    ("1sa", "1SA"), ("1sam", "1SA"), ("1samuel", "1SA"), ("isamuel", "1SA"),
    ("2sa", "2SA"), ("2sam", "2SA"), ("2samuel", "2SA"), ("iisamuel", "2SA"),
    ("1ki", "1KI"), ("1kgs", "1KI"), ("1kings", "1KI"), ("1kin", "1KI"), ("1rois", "1KI"),
    ("2ki", "2KI"), ("2kgs", "2KI"), ("2kings", "2KI"), ("2kin", "2KI"), ("2rois", "2KI"),
    ("1ch", "1CH"), ("1chr", "1CH"), ("1chron", "1CH"), ("1chronicles", "1CH"),
    ("2ch", "2CH"), ("2chr", "2CH"), ("2chron", "2CH"), ("2chronicles", "2CH"),
    ("ezr", "EZR"), ("ezra", "EZR"),
    ("neh", "NEH"), ("nehemiah", "NEH"),
    ("est", "EST"), ("esth", "EST"), ("esther", "EST"),
    ("job", "JOB"),
    ("psa", "PSA"), ("ps", "PSA"), ("psalm", "PSA"), ("psalms", "PSA"), ("pss", "PSA"),
    ("pro", "PRO"), ("prov", "PRO"), ("proverbs", "PRO"),
    ("ecc", "ECC"), ("eccl", "ECC"), ("ecclesiastes", "ECC"),
    ("sng", "SNG"), ("song", "SNG"), ("songofsolomon", "SNG"), ("canticles", "SNG"), ("cant", "SNG"),
    ("isa", "ISA"), ("es", "ISA"), ("isaiah", "ISA"),  # "Es." = French "Esaïe"
    ("jer", "JER"), ("jeremiah", "JER"), ("jer", "JER"),
    ("lam", "LAM"), ("lamentations", "LAM"),
    ("ezk", "EZK"), ("eze", "EZK"), ("ezek", "EZK"), ("ezekiel", "EZK"),
    ("dan", "DAN"), ("daniel", "DAN"),
    ("hos", "HOS"), ("hosea", "HOS"),
    ("jol", "JOL"), ("joel", "JOL"),
    ("amo", "AMO"), ("amos", "AMO"),
    # Deliberately NOT aliasing bare "Am" -> Amos: it only ever appears (once) in the
    # Schaff Belgic footnotes file kept purely as documentary evidence (not parsed by
    # this script — build_belgic() reads the thewestminsterstandard.org rendering
    # instead), and "am" is too common an English word to risk misreading elsewhere.
    ("oba", "OBA"), ("obad", "OBA"), ("obadiah", "OBA"),
    ("jon", "JON"), ("jonah", "JON"),
    ("mic", "MIC"), ("micah", "MIC"), ("mich", "MIC"),  # "Mich." = French "Michée"
    ("nam", "NAM"), ("nah", "NAM"), ("nahum", "NAM"),
    ("hab", "HAB"), ("habakkuk", "HAB"),
    ("zep", "ZEP"), ("zeph", "ZEP"), ("zephaniah", "ZEP"),
    ("hag", "HAG"), ("haggai", "HAG"),
    ("zec", "ZEC"), ("zech", "ZEC"), ("zechariah", "ZEC"),
    ("mal", "MAL"), ("malachi", "MAL"),
    ("mat", "MAT"), ("matt", "MAT"), ("matthew", "MAT"),
    ("mrk", "MRK"), ("mark", "MRK"), ("marc", "MRK"),
    ("luk", "LUK"), ("luke", "LUK"), ("luc", "LUK"),
    ("jhn", "JHN"), ("john", "JHN"), ("jean", "JHN"), ("1jean", "1JN"), ("2jean", "2JN"), ("3jean", "3JN"),
    ("act", "ACT"), ("acts", "ACT"),
    ("rom", "ROM"), ("romans", "ROM"),
    ("1co", "1CO"), ("1cor", "1CO"), ("1corinthians", "1CO"), ("icorinthians", "1CO"),
    ("2co", "2CO"), ("2cor", "2CO"), ("2corinthians", "2CO"), ("iicorinthians", "2CO"),
    ("gal", "GAL"), ("galatians", "GAL"),
    ("eph", "EPH"), ("ephesians", "EPH"),
    ("php", "PHP"), ("phil", "PHP"), ("philippians", "PHP"),
    ("col", "COL"), ("colossians", "COL"),
    ("1th", "1TH"), ("1thess", "1TH"), ("1thessalonians", "1TH"), ("ithessalonians", "1TH"), ("1thes", "1TH"),
    ("2th", "2TH"), ("2thess", "2TH"), ("2thessalonians", "2TH"), ("iithessalonians", "2TH"), ("2thes", "2TH"),
    ("1ti", "1TI"), ("1tim", "1TI"), ("1timothy", "1TI"), ("itimothy", "1TI"),
    ("2ti", "2TI"), ("2tim", "2TI"), ("2timothy", "2TI"), ("iitimothy", "2TI"),
    ("tit", "TIT"), ("titus", "TIT"),
    ("phm", "PHM"), ("philem", "PHM"), ("philemon", "PHM"),
    ("heb", "HEB"), ("hebrews", "HEB"), ("heb", "HEB"),
    ("jas", "JAS"), ("james", "JAS"), ("jacq", "JAS"),  # "Jacq." = French "Jacques"
    ("1pe", "1PE"), ("1pet", "1PE"), ("1peter", "1PE"), ("ipeter", "1PE"), ("pier", "1PE"), ("1pier", "1PE"),
    ("2pe", "2PE"), ("2pet", "2PE"), ("2peter", "2PE"), ("iipeter", "2PE"), ("2pier", "2PE"),
    ("1jn", "1JN"), ("1john", "1JN"), ("ijohn", "1JN"),
    ("2jn", "2JN"), ("2john", "2JN"), ("iijohn", "2JN"),
    ("3jn", "3JN"), ("3john", "3JN"), ("iiijohn", "3JN"),
    ("jud", "JUD"), ("jude", "JUD"),
    ("rev", "REV"), ("revelation", "REV"), ("apoc", "REV"), ("apocal", "REV"),
]
BOOK_ALIASES = {}
for alias, code in _ALIAS_PAIRS:
    BOOK_ALIASES.setdefault(alias, code)
# Digit-prefixed forms ("1 Cor", "I Cor", "First Cor") normalize the same way; handled in
# normalize_book() below rather than enumerated exhaustively here.

_ROMAN_RE = re.compile(r'^[ivxlcdm]+$', re.I)

# Single-chapter books: a citation giving only one number after the book name
# ("Jud. 6", "2 Jean 10", "Phlm 6") means verse N of chapter 1, not "chapter N".
_SINGLE_CHAPTER_BOOKS = {"OBA", "PHM", "2JN", "3JN", "JUD"}


def roman_to_int(s):
    vals = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100, 'd': 500, 'm': 1000}
    s = s.lower()
    total = 0
    prev = 0
    for ch in reversed(s):
        v = vals[ch]
        total += -v if v < prev else v
        prev = max(prev, v)
    return total


def normalize_book(raw):
    """'1 Cor.' / 'I Cor.' / 'Eph.' / 'Jacq.' / 'Es.' -> USFM code, or None.

    Direct alias lookup is tried first so single-letter-I books like "Isa" (Isaiah)
    are never mistaken for a roman-numeral "I" (1st) prefix — that fallback only
    fires, and only wins, when the direct lookup fails AND the converted form is
    itself a known alias (so "Isa" never becomes "1sa", but "ICorinthians" still
    becomes "1corinthians" -> 1CO).
    """
    s = raw.strip().strip('.').lower()
    s = re.sub(r'[^a-z0-9]', '', s)
    if not s:
        return None
    direct = BOOK_ALIASES.get(s)
    if direct:
        return direct
    m = re.match(r'^(i{1,3})([a-z]+)$', s)
    if m and m.group(1) in ('i', 'ii', 'iii'):
        n = {'i': '1', 'ii': '2', 'iii': '3'}[m.group(1)]
        converted = BOOK_ALIASES.get(n + m.group(2))
        if converted:
            return converted
    return None


# Matches one Scripture citation like "Rom. 8:30", "1 Cor. viii. 6", "Eph.1.4-Eph.1.9",
# "Rom.8:28-39", "Matt.10:29-31". Chapter/verse separator may be '.' ':' or roman-numeral
# chapter with arabic verse (Schaff's Belgic-footnote style, e.g. "Eph. iv. 5").
_REF_TOKEN = re.compile(
    # The book group must be followed by a MANDATORY boundary (a period, or at least
    # one space) before the chapter group. Without this, several book abbreviations
    # (Exod, Lev, Rev, Dan, Mic...) contain roman-numeral letters, and the engine will
    # happily backtrack the (greedy) book group by one letter to feed the roman-chapter
    # alternative — "Exod.21" would otherwise parse as book "Exo" + roman chapter "d"
    # (500) rather than book "Exod" + arabic chapter "21", since that reading also
    # produces a full match. A mandatory boundary means "Exod" is always consumed
    # whole once it is followed by "." or whitespace, so that reading never arises.
    r'(?P<book>[1-3]?\s?[A-Za-zÀ-ÿ]+)(?:\.\s*|\s+)'
    r'(?P<chap>\d+|[ivxlcdm]+)'
    # The verse part is optional — a bare "Exod.21" (no verse) cites a whole chapter.
    r'(?:\s*[.:]\s*'
    # Each verse in a list/range must not be immediately followed by a letter — that
    # would mean it's actually the leading digit of the NEXT book's own citation
    # (e.g. "...2.13-1Pet.2.14"), not a bare verse number continuing this range.
    r'(?P<verses>\d+(?:\s*[-–,]\s*\d+(?![A-Za-z]))*))?'
    r'(?:\s*-\s*(?P<book2>[1-3]?\s?[A-Za-zÀ-ÿ]+)?\.?\s*(?P<chap2>\d+)\.(?P<verse2>\d+))?',
    re.IGNORECASE,
)

_BOUNDS_CACHE = None


def _bounds():
    global _BOUNDS_CACHE
    if _BOUNDS_CACHE is None:
        _BOUNDS_CACHE = load_canon_bounds()
    return _BOUNDS_CACHE


def parse_references(text):
    """Extract every Scripture citation from a free-text proof string into
    [{code, chapter, start, end, ref}], deduplicated, in order of appearance."""
    out = []
    seen = set()
    for m in _REF_TOKEN.finditer(text):
        book = normalize_book(m.group('book'))
        if not book:
            continue
        chap_raw = m.group('chap')
        is_roman = bool(_ROMAN_RE.match(chap_raw))
        if is_roman and not m.group('verses') and not m.group('chap2'):
            # A bare single/short roman-numeral "chapter" with no verse following is
            # almost always a false positive from ordinary prose (e.g. "John chapter
            # three", "by act of..." — "chapter"/"act" start with a roman-numeral
            # letter and "John"/"act" both happen to be book aliases). Every genuine
            # whole-chapter citation actually found in these sources uses arabic
            # numerals ("Exod.21", "Ps.73"), never a bare roman chapter, so this
            # pattern is dropped rather than risk a fabricated citation.
            continue
        chap = roman_to_int(chap_raw) if is_roman else int(chap_raw)
        if not m.group('verses') and not m.group('chap2'):
            if book in _SINGLE_CHAPTER_BOOKS:
                # A single-chapter book cited as "Book N" (e.g. "Jud. 6", "2 Jean 10")
                # means verse N of its one chapter, never "chapter N" — Jude has no
                # chapter 6. Reinterpret the lone number as the verse.
                start = end = chap
                key = (book, 1, start, end)
                if key not in seen:
                    seen.add(key)
                    out.append({"code": book, "chapter": 1, "start": start, "end": end,
                                "ref": _label(book, 1, start, end)})
                continue
            # Whole-chapter citation ("Exod.21", "Ps.73") — expand to every verse of
            # that chapter using the bundled BSB canon's verse counts.
            counts = _bounds().get(book)
            if not counts or not (1 <= chap <= len(counts)):
                REPORT["warnings"].append(f"whole-chapter reference to unknown {book} {chap}")
                continue
            start, end = 1, counts[chap - 1]
            key = (book, chap, start, end)
            if key not in seen:
                seen.add(key)
                out.append({"code": book, "chapter": chap, "start": start, "end": end,
                            "ref": _label(book, chap, start, end)})
            continue
        if m.group('chap2') and m.group('verse2'):
            # cross-chapter range "Eph.1.4-Eph.2.5"
            end_chap = int(m.group('chap2'))
            end_verse = int(m.group('verse2'))
            start_verse = int(re.split(r'[-–,]', m.group('verses'))[0])
            # store as same-chapter-start; end verse belongs to end_chap — represent the
            # span verse-by-verse is out of scope for a single {chapter,start,end} record,
            # so split into two references bridging the chapters is avoided here: keep the
            # literal start chapter/verse through end chapter's verse using `end` as a
            # large sentinel only when chapters match; otherwise emit two entries.
            if end_chap == chap:
                start = start_verse
                end = end_verse
                key = (book, chap, start, end)
                if key not in seen:
                    seen.add(key)
                    out.append({"code": book, "chapter": chap, "start": start, "end": end,
                                "ref": _label(book, chap, start, end)})
            else:
                key = (book, chap, start_verse, start_verse)
                if key not in seen:
                    seen.add(key)
                    out.append({"code": book, "chapter": chap, "start": start_verse, "end": start_verse,
                                "ref": _label(book, chap, start_verse, start_verse)})
                key2 = (book, end_chap, end_verse, end_verse)
                if key2 not in seen:
                    seen.add(key2)
                    out.append({"code": book, "chapter": end_chap, "start": end_verse, "end": end_verse,
                                "ref": _label(book, end_chap, end_verse, end_verse)})
            continue
        verses = re.split(r'\s*,\s*', m.group('verses'))
        for group in verses:
            if '-' in group or '–' in group:
                a, b = re.split(r'[-–]', group, 1)
                start, end = int(a), int(b)
            else:
                start = end = int(group)
            key = (book, chap, start, end)
            if key not in seen:
                seen.add(key)
                out.append({"code": book, "chapter": chap, "start": start, "end": end,
                            "ref": _label(book, chap, start, end)})
    return out


def _label(code, chapter, start, end):
    short = SHORT_NAME.get(code, code)
    if start == end:
        return f"{short} {chapter}:{start}"
    return f"{short} {chapter}:{start}–{end}"


SHORT_NAME = {
    "GEN": "Gen", "EXO": "Exod", "LEV": "Lev", "NUM": "Num", "DEU": "Deut", "JOS": "Josh",
    "JDG": "Judg", "RUT": "Ruth", "1SA": "1 Sam", "2SA": "2 Sam", "1KI": "1 Kings",
    "2KI": "2 Kings", "1CH": "1 Chron", "2CH": "2 Chron", "EZR": "Ezra", "NEH": "Neh",
    "EST": "Esth", "JOB": "Job", "PSA": "Ps", "PRO": "Prov", "ECC": "Eccl", "SNG": "Song",
    "ISA": "Isa", "JER": "Jer", "LAM": "Lam", "EZK": "Ezek", "DAN": "Dan", "HOS": "Hos",
    "JOL": "Joel", "AMO": "Amos", "OBA": "Obad", "JON": "Jonah", "MIC": "Mic", "NAM": "Nah",
    "HAB": "Hab", "ZEP": "Zeph", "HAG": "Hag", "ZEC": "Zech", "MAL": "Mal", "MAT": "Matt",
    "MRK": "Mark", "LUK": "Luke", "JHN": "John", "ACT": "Acts", "ROM": "Rom", "1CO": "1 Cor",
    "2CO": "2 Cor", "GAL": "Gal", "EPH": "Eph", "PHP": "Phil", "COL": "Col", "1TH": "1 Thess",
    "2TH": "2 Thess", "1TI": "1 Tim", "2TI": "2 Tim", "TIT": "Titus", "PHM": "Phlm",
    "HEB": "Heb", "JAS": "Jas", "1PE": "1 Pet", "2PE": "2 Pet", "1JN": "1 John",
    "2JN": "2 John", "3JN": "3 John", "JUD": "Jude", "REV": "Rev",
}


# ---------------------------------------------------------------------------
# BSB canon (for build-time sanity checking; the authoritative check is the Swift test)
# ---------------------------------------------------------------------------

def load_canon_bounds():
    manifest = json.loads(BSB_MANIFEST.read_text())
    bounds = {}
    for b in manifest["books"]:
        bounds[b["code"]] = b["verses"]  # verse count per chapter, 1-indexed by position
    return bounds


def check_ref(bounds, code, chapter, verse):
    counts = bounds.get(code)
    if counts is None:
        return f"unknown book code {code}"
    if not (1 <= chapter <= len(counts)):
        return f"{code} has no chapter {chapter}"
    if not (1 <= verse <= counts[chapter - 1]):
        return f"{code} {chapter} has no verse {verse} (max {counts[chapter - 1]})"
    return None


def html_to_text(path):
    html = path.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(r"<[^>]+>", " ", html)
    text = text.replace("&#8217;", "’").replace("&#8220;", "“").replace("&#8221;", "”")
    text = re.sub(r"&[a-z#0-9]+;", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def references_from_proof_list(proofs_field):
    """nlf-style `Proofs: [{Id, References: [...]}]` -> flat parsed reference list,
    in Id order, deduplicated."""
    out = []
    seen = set()
    for p in sorted(proofs_field, key=lambda p: p.get("Id", 0)):
        blob = "; ".join(p.get("References", []))
        for ref in parse_references(blob):
            key = (ref["code"], ref["chapter"], ref["start"], ref["end"])
            if key not in seen:
                seen.add(key)
                out.append(ref)
    return out


# ---------------------------------------------------------------------------
# WCF — American-revision structure (OPC) + historic 1647 Assembly proof texts
# (nlf, cross-checked against thewestminsterstandard.org), aligned section by
# section with a text-similarity match. Sections genuinely rewritten by the
# American revision (below the match threshold) carry no proof texts; this is
# reported, never silently papered over with a fabricated citation.
# ---------------------------------------------------------------------------

_MATCH_THRESHOLD = 0.75

# WCF 1.2 is only a list of the 66 canonical book names. OPC's page renders it from a
# 3-column HTML table that collapses to garbled reading order once tags are stripped;
# the book list itself is identical in substance to the original, so the original
# (nlf) wording is used directly for this one section rather than the garbled scrape.
_WCF_1_2_OVERRIDE = None  # filled in from nlf at build time


def _norm_wcf(s):
    s = re.sub(r"^\d+\.\s*", "", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    return re.sub(r"[^a-z ]", "", s)


def parse_opc_wcf(raw_text):
    """American-revision chapter/section text (no proofs) from opc.org/wcf.html."""
    idxs = [m.start() for m in re.finditer(r"CHAPTER \d+", raw_text)]
    idxs.append(len(raw_text))
    assert len(idxs) - 1 == 33, f"expected 33 CHAPTER markers, found {len(idxs) - 1}"
    chapters = {}
    for i in range(33):
        chunk = raw_text[idxs[i]:idxs[i + 1]]
        # The final chapter's chunk runs into the page footer/nav; cut it off.
        chunk = chunk.split("The Orthodox Presbyterian Church CONTACT US")[0]
        m = re.match(r"CHAPTER (\d+)\s+(.*?)\s+1\.\s", chunk)
        n = int(m.group(1))
        rest = "1. " + chunk[m.end():]
        cands = [(mm.start(), int(mm.group(1)))
                 for mm in re.finditer(r"(?:^|(?<=\s))(\d{1,2})\.\s+(?=[A-Z])", rest)]
        chosen = []
        expect = 1
        for pos, num in cands:
            if num == expect:
                chosen.append(pos)
                expect += 1
        chosen.append(len(rest))
        sections = [rest[chosen[j]:chosen[j + 1]].strip() for j in range(len(chosen) - 1)]
        chapters[n] = sections
    return chapters


def build_wcf(bounds):
    nlf = json.loads((RAW / "wcf-1647-nlf.json").read_text())
    orig_by_chapter = {}
    for c in nlf["Data"]:
        n = int(c["Chapter"])
        orig_by_chapter[n] = [(s["Content"], references_from_proof_list(s.get("Proofs", [])))
                               for s in c["Sections"]]

    opc_raw = (RAW / "wcf-american-opc.txt").read_text()
    american = parse_opc_wcf(opc_raw)

    chapter_meta = json.loads(
        (ROOT / "Sources/StudyTable/Resources/Confession/wcf-chapters.json").read_text()
    )["chapters"]
    titles = {c["n"]: c["title"] for c in chapter_meta}
    expected_sections = {c["n"]: c["sections"] for c in chapter_meta}

    items = []
    matched_count = 0
    unmatched = []
    for n in range(1, 34):
        am_secs = american[n]
        or_secs = orig_by_chapter.get(n, [])
        if len(am_secs) != expected_sections[n]:
            REPORT["warnings"].append(
                f"WCF {n}: parsed {len(am_secs)} American sections, wcf-chapters.json expects {expected_sections[n]}"
            )
        for ai, atext in enumerate(am_secs):
            sec_num = ai + 1
            if n == 1 and sec_num == 2:
                # Garbled 3-column book-list scrape — use the original (identical in
                # substance) text instead. No proofs either way (a book list cites
                # nothing).
                atext = orig_by_chapter[1][1][0] if len(orig_by_chapter.get(1, [])) > 1 else atext
                proofs = []
            else:
                an = _norm_wcf(atext)
                best_idx, best_ratio = -1, 0.0
                for oi, (otext, _) in enumerate(or_secs):
                    r = difflib.SequenceMatcher(None, an, _norm_wcf(otext)).ratio()
                    if r > best_ratio:
                        best_idx, best_ratio = oi, r
                if best_ratio >= _MATCH_THRESHOLD:
                    proofs = or_secs[best_idx][1]
                    matched_count += 1
                else:
                    proofs = []
                    unmatched.append(f"WCF {n}.{sec_num} (best match {n}.{best_idx + 1 if best_idx >= 0 else '?'} ratio {best_ratio:.2f})")
            clean_text = re.sub(r"^\d+\.\s*", "", atext).strip()
            items.append({
                "id": f"{n}.{sec_num}",
                "label": f"WCF {n}.{sec_num}",
                "heading": titles.get(n, f"Chapter {n}"),
                "text": clean_text,
                "proofs": proofs,
            })
    REPORT["documents"]["wcf"] = {
        "items": len(items),
        "sectionsWithHistoricProofs": matched_count,
        "sectionsWithoutHistoricProofs": len(unmatched),
        "unmatchedSections": unmatched,
    }
    return {
        "id": "wcf",
        "title": "The Westminster Confession of Faith",
        "shortTitle": "WCF",
        "year": 1646,
        "translation": "American revision (structure/wording per the Orthodox Presbyterian Church, opc.org/wcf.html); "
                        "Scripture proofs are the Westminster Assembly's own 1647 citations (public-domain 1647 text, "
                        "cross-checked against thewestminsterstandard.org) carried over wherever the American wording "
                        "is substantially unchanged from the original — see standards-sources/SOURCES.md for the "
                        "small number of sections (American-only revisions) that carry no historic citation.",
        "sourceURL": "https://opc.org/wcf.html",
        "license": "Public domain (17th-century ecclesiastical confession; American-revision wording as presented by "
                    "the Orthodox Presbyterian Church, a denominational doctrinal standard published without "
                    "copyright restriction).",
        "kind": "confession",
        "items": items,
    }


# ---------------------------------------------------------------------------
# WLC — 1647 Assembly text + proofs (nlf), used directly.
# ---------------------------------------------------------------------------

def build_wlc():
    nlf = json.loads((RAW / "wlc-1647-nlf.json").read_text())
    items = []
    for q in nlf["Data"]:
        items.append({
            "id": f"Q{q['Number']}",
            "label": f"WLC Q{q['Number']}",
            "question": q["Question"],
            "text": q["Answer"],
            "proofs": references_from_proof_list(q.get("Proofs", [])),
        })
    REPORT["documents"]["wlc"] = {"items": len(items)}
    return {
        "id": "wlc",
        "title": "The Larger Catechism",
        "shortTitle": "WLC",
        "year": 1647,
        "translation": "Original 1647 Westminster Assembly text (public domain; digitized from the 1647 "
                        "'Humble Advice' Assembly printing, archive.org).",
        "sourceURL": "https://archive.org/details/humbleadviceofas200west/page/108/mode/2up",
        "license": "Public domain (17th-century ecclesiastical document).",
        "kind": "catechism",
        "items": items,
    }


# ---------------------------------------------------------------------------
# WSC — 1647 Assembly Q/A text (nlf) + the traditional annexed Scripture-proof
# apparatus (thewestminsterstandard.org), matched by question number.
# ---------------------------------------------------------------------------

_CITE_START_LETTERED = re.compile(r"(?:[1-3]\s?)?[A-Z][a-z]{1,10}\.?\s*\d{1,3}[:.]\d{1,3}")


def build_wsc():
    nlf = json.loads((RAW / "wsc-1647-text-nlf.json").read_text())
    text = html_to_text(RAW / "wsc-proofs-thewestminsterstandard.html")
    idxs = [m.start() for m in re.finditer("chief end of man", text)]
    body = text[idxs[1] - 20:]
    cands = [m.start() for m in re.finditer(r"Q\.\s*\d{1,3}\.\s", body)]
    cands.append(len(body))
    blocks = [body[cands[i]:cands[i + 1]] for i in range(len(cands) - 1)]
    assert len(blocks) == 107, f"expected 107 WSC proof blocks, found {len(blocks)}"

    items = []
    missing_proofs = []
    for i, q in enumerate(nlf["Data"]):
        blk = blocks[i]
        am = re.search(r"A\.\s", blk)
        rest = blk[am.end():] if am else blk
        cm = _CITE_START_LETTERED.search(rest)
        proofs = parse_references(rest[cm.start():]) if cm else []
        if not proofs:
            missing_proofs.append(q["Number"])
        items.append({
            "id": f"Q{q['Number']}",
            "label": f"WSC Q{q['Number']}",
            "question": q["Question"],
            "text": q["Answer"],
            "proofs": proofs,
        })
    REPORT["documents"]["wsc"] = {"items": len(items), "missingProofs": missing_proofs}
    return {
        "id": "wsc",
        "title": "The Shorter Catechism",
        "shortTitle": "WSC",
        "year": 1647,
        "translation": "Original 1647 Westminster Assembly Q/A text (public domain; archive.org 1647 printing) with "
                        "the traditional annexed Scripture-proof apparatus (public-domain 17th-century text).",
        "sourceURL": "https://archive.org/details/bim_early-english-books-1641-1700_the-humble-advice-of-the_westminster-assembly-of-_1647_0",
        "license": "Public domain (17th-century ecclesiastical document).",
        "kind": "catechism",
        "items": items,
    }


# ---------------------------------------------------------------------------
# Heidelberg Catechism — traditional public-domain English translation (matches
# both ccel.org/creeds/heidelberg-cat.html and thewestminsterstandard.org verbatim;
# NOT the modern CRC/Faith Alive copyrighted translation, which reads
# "belong—body and soul, in life and in death—to my faithful Savior") with its
# lettered proof-text apparatus.
# ---------------------------------------------------------------------------

_HC_HEADINGS_TO_STRIP = [
    "The First Part", "The Second Part", "The Third Part",
    "Of Holy Baptism", "Of The Holy Supper Of Our Lord Jesus Christ", "Of Prayer",
]


def build_hc():
    text = html_to_text(RAW / "heidelberg-ccel.html")
    for h in _HC_HEADINGS_TO_STRIP:
        text = text.replace(h, " ")
    idx = text.find("Question 1.")
    body = "1. Lord's Day " + text[idx:]
    end = body.find("End of the Catechism")
    body = body[:end]

    tokens = []
    for m in re.finditer(r"(?P<ld>(\d{1,2})\.?\s+Lord.s [Dd]ay)|(?P<q>Q(?:uestion)?\.?\s*(\d{1,3})\.\s)", body):
        if m.group("ld"):
            tokens.append(("LD", int(m.group(2)), m.start(), m.end()))
        else:
            tokens.append(("Q", int(m.group(4)), m.start(), m.end()))
    assert sum(1 for t in tokens if t[0] == "LD") == 52
    assert sum(1 for t in tokens if t[0] == "Q") == 129

    cite_start = re.compile(r"(?:\([a-z]\)\s*)?(?:[1-3]\s?)?[A-Z][a-z]{1,10}\.?\s*\d{1,3}[:.]\d{1,3}")
    current_ld = None
    items = []
    no_proof_expected = {23, 24, 68, 83}  # 23 = the bare Apostles' Creed recitation; the rest structural/enumerating
    unexpected_missing = []
    for i, t in enumerate(tokens):
        if t[0] == "LD":
            current_ld = t[1]
            continue
        qn = t[1]
        start, end_pos = t[3], (tokens[i + 1][2] if i + 1 < len(tokens) else len(body))
        block = body[start:end_pos].strip()
        am = re.search(r"\bA\.\s|\bAnswer\.\s", block)
        question = block[:am.start()].strip().rstrip("?") + "?"
        rest = block[am.end():]
        cm = cite_start.search(rest)
        if cm:
            answer_raw, cites = rest[:cm.start()], rest[cm.start():]
        else:
            answer_raw, cites = rest, ""
        answer = re.sub(r"\([a-z]\)", "", answer_raw)
        answer = re.sub(r"\s+([.,;:])", r"\1", answer)
        answer = re.sub(r"\s+", " ", answer).strip()
        proofs = parse_references(cites)
        if not proofs and qn not in no_proof_expected:
            unexpected_missing.append(qn)
        items.append({
            "id": f"Q{qn}",
            "label": f"HC Q{qn}",
            "heading": f"Lord's Day {current_ld}",
            "question": question,
            "text": answer,
            "proofs": proofs,
        })
    REPORT["documents"]["hc"] = {
        "items": len(items),
        "noProofExpected": sorted(no_proof_expected),
        "unexpectedMissingProofs": unexpected_missing,
    }
    return {
        "id": "hc",
        "title": "The Heidelberg Catechism",
        "shortTitle": "HC",
        "year": 1563,
        "translation": "Traditional public-domain English translation with its lettered Scripture-proof apparatus "
                        "(reproduced identically, independently, at ccel.org/creeds/heidelberg-cat.html and "
                        "thewestminsterstandard.org/heidelberg-catechism/). Deliberately NOT the modern "
                        "1975/1988/2011 CRC & RCA joint translation, which is copyrighted by Faith Alive Christian "
                        "Resources and reads \"belong—body and soul, in life and in death—to my faithful "
                        "Savior\" — verified as textually distinct from this translation's \"belong unto my faithful "
                        "Saviour Jesus Christ.\"",
        "sourceURL": "https://www.ccel.org/creeds/heidelberg-cat.html",
        "license": "Public domain (traditional English translation, pre-modern-copyright diction; not the "
                    "restricted modern CRC/Faith Alive translation).",
        "kind": "catechism",
        "items": items,
    }


# ---------------------------------------------------------------------------
# Belgic Confession — the RCA-authorized English translation Schaff reprinted in
# Creeds of Christendom vol. 3 (1877/1889, CCEL: "Rights: Public Domain"), read
# here from thewestminsterstandard.org's clean single-language rendering of the
# SAME translation (verified word-for-word against Schaff's text; both are
# textually distinct from the modern CRC 2011/Faith Alive translation, which was
# confirmed copyrighted and explicitly restricts reproduction — see SOURCES.md).
# ---------------------------------------------------------------------------

# A few articles' short headings don't reliably separate from body text with the
# generic heuristic (the body's first sentence doesn't start with "We"); hand-
# verified against the raw source (thewestminsterstandard.org/the-belgic-confession/).
_BELGIC_TITLE_OVERRIDES = {
    8: "That God is one in Essence, yet nevertheless distinguished in three Persons",
    9: "The proof of the foregoing article of the Trinity of persons in one God.",
    32: "Of the Order and Discipline of the Church",
    37: "Of the Last Judgment",
}


def _belgic_schaff_footnote_proofs():
    """Per-article proof texts from Schaff's bilingual Belgic Confession excerpt.

    Its footnote apparatus (316 footnotes across the 37 articles — far richer than
    the handful of citations written directly into thewestminsterstandard.org's
    prose-only rendering) only carries footnote markers on the French column, but
    the marker *numbers* are language-agnostic, so this only needs to find which
    numbers fall within each article's span and resolve each number's definition —
    it never needs to separate the French and English text.
    """
    text = (RAW / "belgic-confession-schaff.txt").read_text()
    roman_pat = r"Art\.\s+([IVXLC]+)\.?\s+Art\.\s+\1\."
    starts = [m.start() for m in re.finditer(roman_pat, text)]
    assert len(starts) == 37, f"expected 37 Belgic article headers in the Schaff excerpt, found {len(starts)}"
    # The footnote *definitions* block follows a long underscore divider after the
    # last article's own text; everything from there on is definitions, not article
    # body, and must be excluded when scanning articles for their own citation
    # markers (article 37's span would otherwise swallow every later definition's
    # own bracketed number as if it were one more citation inside article 37).
    divider = max(m.start() for m in re.finditer(r"_{5,}", text))
    body_end = divider
    starts.append(body_end)

    fn_defs = {}
    for m in re.finditer(r"\[(\d+)\]\s*(.*?)(?=\n\s*\[\d+\]|\Z)", text[divider:], re.S):
        fn_defs[int(m.group(1))] = re.sub(r"\s+", " ", m.group(2)).strip()

    per_article = {}
    for i in range(37):
        span = text[starts[i]:starts[i + 1]]
        nums = sorted(set(int(n) for n in re.findall(r"\[(\d+)\]", span)))
        refs = []
        seen = set()
        for n in nums:
            defn = fn_defs.get(n)
            if not defn:
                REPORT["warnings"].append(f"Belgic Art.{i + 1}: footnote [{n}] has no definition")
                continue
            for ref in parse_references(defn):
                key = (ref["code"], ref["chapter"], ref["start"], ref["end"])
                if key not in seen:
                    seen.add(key)
                    refs.append(ref)
        per_article[i + 1] = refs
    return per_article


def build_belgic():
    text = (RAW / "belgic-confession-thewestminsterstandard.txt").read_text()
    schaff_proofs = _belgic_schaff_footnote_proofs()

    cands = [(m.start(), int(m.group(1)))
             for m in re.finditer(r"(?:^|(?<=[.\s]))(\d{1,2})\.\s+(?=[A-Z])", text)]
    chosen = []
    expect = 1
    for pos, n in cands:
        if n == expect:
            chosen.append(pos)
            expect += 1
    assert expect - 1 == 37, f"expected 37 Belgic articles, found {expect - 1}"
    chosen.append(len(text))
    articles = [text[chosen[i]:chosen[i + 1]].strip() for i in range(len(chosen) - 1)]

    items = []
    for i, a in enumerate(articles, start=1):
        body = re.sub(r"^\d+\.\s+", "", a)
        if i in _BELGIC_TITLE_OVERRIDES:
            title = _BELGIC_TITLE_OVERRIDES[i]
            rest = body[len(title):].strip() if body.startswith(title) else body
        else:
            m = re.search(r"\bWe\b", body, re.IGNORECASE)
            if m and 0 < m.start() < 90:
                title, rest = body[:m.start()].strip(), body[m.start():]
            else:
                title, rest = None, body
        # Merge this translation's own inline citations with the richer Schaff
        # footnote apparatus for the same article (deduplicated; Schaff's footnotes
        # are the primary source of proof-text depth here).
        proofs = list(schaff_proofs.get(i, []))
        seen = {(p["code"], p["chapter"], p["start"], p["end"]) for p in proofs}
        for ref in parse_references(rest):
            key = (ref["code"], ref["chapter"], ref["start"], ref["end"])
            if key not in seen:
                seen.add(key)
                proofs.append(ref)
        items.append({
            "id": f"Art.{i}",
            "label": f"Belgic Art. {i}",
            "heading": title,
            "text": rest.strip(),
            "proofs": proofs,
        })
    REPORT["documents"]["bc"] = {"items": len(items),
                                  "itemsWithProofs": sum(1 for it in items if it["proofs"])}
    return {
        "id": "bc",
        "title": "The Belgic Confession",
        "shortTitle": "Belgic",
        "year": 1561,
        "translation": "The Reformed (Dutch) Church in America's authorized 19th-century English translation, as "
                        "reprinted by Philip Schaff in Creeds of Christendom, vol. III (1877/1889; CCEL edition "
                        "explicitly marked \"Rights: Public Domain\"), read here in thewestminsterstandard.org's "
                        "single-language rendering of the same translation (verified word-for-word identical to "
                        "Schaff's text). Deliberately NOT the modern text bundled by the Christian Reformed Church's "
                        "official BelgicConfession.pdf (copyright Faith Alive Christian Resources, 2011 — confirmed "
                        "by direct comparison: that edition reads \"single and simple spiritual being\" and \"the "
                        "Creation and Fall of Humanity\"; this one reads \"one only simple and spiritual Being\" and "
                        "\"the Creation and Fall of Man,\" matching Schaff's 1877 text, not the 2011 revision).",
        "sourceURL": "https://thewestminsterstandard.org/the-belgic-confession/",
        "license": "Public domain (Schaff, Creeds of Christendom vol. III, 1877/1889 — CCEL: \"Rights: Public "
                    "Domain\"; see scripts/standards-sources/raw/belgic-confession-schaff.txt for the bilingual "
                    "French/English original with its footnoted proof texts).",
        "kind": "confession",
        "items": items,
    }


# ---------------------------------------------------------------------------
# Canons of Dort — nlf's Articles text verified word-for-word against Schaff's
# public-domain RCA-translation reprint (Creeds of Christendom vol. III); its
# Rejection-of-Errors text (which Schaff's abridged RCA reprint omits) verified
# against the URCNA's own confessional-standard text, published without a
# copyright notice or restriction. Proof texts are this translation's own
# inline Scripture quotations/citations (its historic apparatus — this
# document does not use WCF-style lettered footnotes).
# ---------------------------------------------------------------------------

def build_canons():
    nlf = json.loads((RAW / "canons-of-dort-nlf.json").read_text())
    articles = []
    withheld_rejections = []
    for head in nlf["Data"]:
        head_n = head["Chapter"]  # "1", "2", "3&4", "4" (nlf's own numbering for the heads)
        # nlf mislabels the Fifth Head of Doctrine ("Of the Perseverance of the Saints") as
        # Chapter "4" — a straight duplicate of the Third-and-Fourth Head's own "4" component.
        # Every standard reference to the Canons numbers it the Fifth Head; corrected here so
        # citations read "Canons of Dort 5.A1", not a second, colliding "4.A1".
        if head_n == "4" and head["Title"] == "Of the Perseverance of the Saints":
            head_n = "5"
        for sec in head["Sections"]:
            sec_id = sec["Section"]  # "A1".."A9" (article), "R1".."R9" (rejection of errors)
            is_article = sec_id.startswith("A")
            kind = "Article" if is_article else "Rejection of Errors"
            num = sec_id[1:]
            item = {
                "id": f"{head_n}.{sec_id}",
                "label": f"Canons of Dort {head_n}.{kind[0]}{num}",
                "heading": f"Head {head_n}: {head['Title']} — {kind} {num}",
                "text": sec["Content"].strip(),
                "proofs": parse_references(sec["Content"]),
            }
            if is_article:
                articles.append(item)
            else:
                # WITHHELD, not shipped — see the long comment below. Parsing is kept (not
                # deleted) so re-enabling this is a one-line change once a public-domain
                # translation is confirmed, but `items` below only ever gets `articles`.
                withheld_rejections.append(item)

    # --------------------------------------------------------------------------------------
    # Rejection of Errors (34 items) — WITHHELD from 0.7.0 pending licence verification.
    #
    # The Articles above are positively public domain (Schaff/CCEL's explicit "Rights: Public
    # Domain" marking, verified word-for-word). The Rejection-of-Errors text has no equivalent
    # positive evidence: it isn't in Schaff's reprint at all (his own editorial note says the
    # RCA Constitution he reprinted from omits it), so it was sourced from URCNA's published
    # confessional-standard page instead, on the reasoning that a denomination publishing its
    # own doctrinal standard with no copyright notice is low legal risk. On reflection (per
    # ground rule 6: unclear licence -> don't ship) that reasoning is an *absence* of a
    # restriction, not *positive* evidence of public-domain status, and the wording itself
    # reads like the mid-20th-century CRC Psalter Hymnal rendering of the Canons, whose actual
    # US copyright/renewal status this workstream has not been able to confirm either way.
    # Rather than ship something merely unobjected-to, the 34 Rejection-of-Errors items are
    # parsed (so the code isn't lost) but never emitted into cd.json or the reverse index.
    #
    # Candidate replacements for a future pass, to be verified the same way the Articles were
    # (an explicit, positive PD declaration, not just an absent copyright notice):
    #   - Thomas Scott's 1818 English translation of the Acts of the Synod of Dort (includes
    #     the Rejection of Errors in full; pre-1929, unambiguously PD).
    #   - Any verified pre-1931 US edition/reprint of the Canons (works published in the US
    #     before 1929 are categorically PD; 1929-1963 works needed a renewal that a great many
    #     denominational reprints never filed, but that has to be checked per edition, not
    #     assumed).
    # --------------------------------------------------------------------------------------
    items = articles

    REPORT["documents"]["cd"] = {
        "items": len(items),
        "articles": len(articles),
        "rejections": 0,
        "rejectionsParsedButWithheld": len(withheld_rejections),
        "itemsWithProofs": sum(1 for it in items if it["proofs"]),
    }
    return {
        "id": "cd",
        "title": "The Canons of the Synod of Dort",
        "shortTitle": "Canons of Dort",
        "year": 1619,
        "translation": "Positive articles only (the Rejection of Errors is withheld pending licence "
                        "verification — see scripts/standards-sources/SOURCES.md and the long comment in "
                        "build_canons()). The Reformed (Dutch) Church in America's authorized translation, as "
                        "reprinted by Schaff (Creeds of Christendom vol. III, 1877/1889, public domain) — verified "
                        "word-for-word identical.",
        "sourceURL": "https://github.com/NonlinearFruit/Creeds.json (data structure; text verified against "
                     "Schaff/CCEL — see SOURCES.md)",
        "license": "Public domain (Schaff/CCEL, explicit public-domain marking). Articles only — see SOURCES.md "
                    "for why the Rejection of Errors is withheld from this build.",
        "kind": "canons",
        "items": items,
    }


# ---------------------------------------------------------------------------
# Assembly, reverse index, and output
# ---------------------------------------------------------------------------

def build_reverse_index(documents):
    index = {}
    mismatches = []
    bounds = load_canon_bounds()
    for doc in documents:
        for item in doc["items"]:
            # One item can cite the same verse twice over (an individual verse proof
            # plus a range that also covers it, e.g. WCF 3.6 cites both Rom 8:30 and
            # Rom 8:28-39) — dedupe per (doc, item, verse) so the index lists the
            # section once, not once per overlapping proof.
            item_seen_keys = set()
            for proof in item["proofs"]:
                code, chapter = proof["code"], proof["chapter"]
                for verse in range(proof["start"], proof["end"] + 1):
                    problem = check_ref(bounds, code, chapter, verse)
                    if problem:
                        mismatches.append(f"{doc['id']} {item['id']}: {problem} (from {proof['ref']})")
                        continue
                    key = f"{code}.{chapter}.{verse}"
                    if (doc["id"], item["id"], key) in item_seen_keys:
                        continue
                    item_seen_keys.add((doc["id"], item["id"], key))
                    index.setdefault(key, []).append({"doc": doc["id"], "item": item["id"]})
    REPORT["reverseIndex"] = {"keys": len(index), "versificationMismatches": mismatches}
    return index


def main():
    report_only = "--report-only" in sys.argv
    bounds = load_canon_bounds()

    documents = [
        build_wcf(bounds),
        build_wlc(),
        build_wsc(),
        build_hc(),
        build_belgic(),
        build_canons(),
    ]
    reverse_index = build_reverse_index(documents)

    if report_only:
        print(json.dumps(REPORT, indent=1))
        return

    staging = Path("/private/tmp/st-standards-build")
    if staging.exists():
        import shutil
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    for doc in documents:
        out = dict(doc)
        (staging / f"{doc['id']}.json").write_text(
            json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    proof_index_doc = {
        "schema": 1,
        "note": "Reverse index: verse key (\"ROM.8.30\") -> confessional/catechism sections citing it as a proof "
                "text. Cited as a proof text by the confession itself — not an app judgment.",
        "index": reverse_index,
    }
    (staging / "proof-index.json").write_text(
        json.dumps(proof_index_doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    report_path = ROOT / "scripts" / "standards-sources" / "build-report.json"
    report_path.write_text(json.dumps(REPORT, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    # Atomic swap into the bundled resource directory.
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for f in staging.iterdir():
        (OUT_DIR / f.name).write_bytes(f.read_bytes())

    print(f"Wrote {len(documents)} documents + proof-index.json to {OUT_DIR}")
    print(f"Report: {report_path}")
    total_items = sum(len(d["items"]) for d in documents)
    total_proofs = sum(len(it["proofs"]) for d in documents for it in d["items"])
    print(f"Total items: {total_items}, total proof references: {total_proofs}, reverse-index keys: {len(reverse_index)}")
    if REPORT["reverseIndex"]["versificationMismatches"]:
        print(f"WARNING: {len(REPORT['reverseIndex']['versificationMismatches'])} versification mismatches — see build-report.json")


if __name__ == "__main__":
    main()
