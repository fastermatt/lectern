#!/usr/bin/env python3
"""Build compact, book-scoped offline study indexes (schema 2).

Deterministic: identical inputs produce byte-identical output. Every entry has a
stable content-derived ID, a source-registry reference, an explicit range basis,
and cleaning/dropping decisions are recorded in data/study-build-report.json.

Nothing here decides theological agreement. Review states describe *how an entry
was obtained*, never whether it is doctrinally approved; Westminster links live in
the separately curated Resources/Confession/wcf-links.json.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

SCHEMA = 3
ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "work-content"
OUT = ROOT / "Sources/StudyTable/Resources/Study"
REPORT = ROOT / "data/study-build-report.json"
CALVIN = WORK / "pillar-commentary-data-main/c/calvin"
HELLOAO = WORK / "helloao"
FATHERS_PROFILES_SOURCE = WORK / "fathers-profiles.source.json"

# Source registry: one record per upstream dataset. Entries reference it by id, so the
# per-entry payload stays small and provenance is stated exactly once.
#
# "mhcc" (Matthew Henry's Concise Commentary) was retired 2026-09-22 in favor of the
# unabridged "matthew-henry" (Complete Commentary on the Whole Bible) -- see
# CONTENT-SOURCES.md and data/study-build-report.json for the retirement note. Its one WCF
# candidate link was re-pointed, not deleted (scripts/wcf-links.py). Restored 2026-09-23
# (workstream E, 0.7 wave 2, E3) in a narrow, *gap-only* role: parsed again from the same
# work-content/mhcc.txt, but only emitted for the specific chapters where the unabridged
# Complete has no entry at all, so a documented gap in Henry's own voice is backfilled by his
# own (abridged) words rather than left silent. It is not restored as a general second Henry
# voice -- the retirement's own reasoning (two Henry cards per verse is clutter) still holds
# everywhere the Complete actually has an entry.
SOURCES = {
    "matthew-henry": {
        "title": "Matthew Henry's Commentary on the Whole Bible (Complete, unabridged)",
        "short": "HelloAO · Matthew Henry Complete",
        "publisher": "Digitized by the HelloAO Free Use Bible API from the historic public-domain "
                     "Commentary on the Whole Bible",
        "url": "https://bible.helloao.org/api/c/matthew-henry/",
        "license": "Public Domain Mark 1.0",
        "review": {"state": "source-attributed",
                   "note": "Attributed to a Reformed author. Not reviewed against the Westminster Confession. "
                           "Henry completed Genesis through Acts himself; Romans onward was finished after his "
                           "1714 death by other nonconformist ministers from his notes -- long-published and "
                           "treated as one continuous work, as it is here. Verified 2026-09-22, directly against "
                           "this digitization's own books.json and chapter files, not assumed: it covers 65 of 66 "
                           "books (no Song of Solomon at all) and three of those 65 are themselves truncated -- "
                           "2 Samuel stops at chapter 22 of 24, Jonah at chapter 1 of 4, and Matthew at chapter 18 "
                           "of 28 (missing 19-28: the Olivet Discourse, Last Supper, Gethsemane, crucifixion and "
                           "resurrection accounts). A further 8 chapters are individually empty within otherwise-"
                           "complete books (Numbers 31-35, Joshua 22-23, Psalm 72) -- confirmed genuinely empty "
                           "in the source ('content': []), not a parsing failure. None of this leaves any chapter "
                           "of the Bible with zero Reformed commentary overall -- Calvin and/or Gill still cover "
                           "every gap -- but Henry's own voice is absent there. See data/study-build-report.json."},
    },
    "john-gill": {
        "title": "John Gill's Exposition of the Old and New Testament",
        "short": "HelloAO · John Gill's Exposition",
        "publisher": "Digitized by the HelloAO Free Use Bible API from the historic public-domain Exposition",
        "url": "https://bible.helloao.org/api/c/john-gill/",
        "license": "Public Domain Mark 1.0",
        "review": {"state": "source-attributed",
                   "note": "Verse-by-verse across all 66 books. Not reviewed against the Westminster Confession. "
                           "Moved from the Reformed bank into the new Tier-2 Exegetes bank 2026-09-23 (workstream "
                           "E, 0.7 wave 2, E1): Gill did not subscribe to the Westminster Standards (he stood in "
                           "the London/Second London Baptist Confession tradition, a Particular Baptist, labelled "
                           "as such on every card). WORKPLAN-0.7.md's E1 instruction resolves the tension "
                           "CONTENT-ROADMAP.md flagged 2026-09-22 (an earlier pass had filed Gill Tier 1 pending "
                           "human review): Matt's original spec -- confessional Baptist authors are Tier 2, "
                           "explicitly labelled -- is authoritative and is what ships now."},
    },
    "keil-delitzsch": {
        "title": "Carl Friedrich Keil and Franz Delitzsch's Old Testament Commentary",
        "short": "HelloAO · Keil & Delitzsch",
        "publisher": "Digitized by the HelloAO Free Use Bible API from the historic public-domain Old Testament "
                     "Commentary",
        "url": "https://bible.helloao.org/api/c/keil-delitzsch/",
        "license": "Public Domain Mark 1.0",
        "review": {"state": "source-attributed",
                   "note": "New 2026-09-23 (workstream E, 0.7 wave 2, E2): 19th-century Old Testament commentary "
                           "by two German Lutheran scholars, Carl Friedrich Keil (1807-1888) and Franz Delitzsch "
                           "(1813-1890). Filed Tier 2 Exegetes, labelled 'Lutheran' on every card -- not "
                           "confessionally Reformed, not reviewed against the Westminster Confession. Old "
                           "Testament only (39 books per the source's own manifest). This digitization's own "
                           "fetch record (work-content/helloao/keil-delitzsch/_fetch-manifest.json) shows 11 "
                           "individual chapters returned HTTP 404 at the source (Exod 37-38, Num 17, Job 25, Ps "
                           "101/117/131/133, Ezek 4/5/36) and Song of Solomon has zero chapters at the source "
                           "despite being listed in its books.json -- both are upstream gaps, not a parsing "
                           "defect; see data/study-build-report.json."},
    },
    "jamieson-fausset-brown": {
        "title": "Jamieson, Fausset & Brown's Commentary Critical and Explanatory on the Whole Bible",
        "short": "HelloAO · Jamieson-Fausset-Brown",
        "publisher": "Digitized by the HelloAO Free Use Bible API from the historic public-domain Commentary "
                     "Critical and Explanatory on the Whole Bible",
        "url": "https://bible.helloao.org/api/c/jamieson-fausset-brown/",
        "license": "Public Domain Mark 1.0",
        "review": {"state": "source-attributed",
                   "note": "New 2026-09-23 (workstream E, 0.7 wave 2, E2): 19th-century whole-Bible commentary by "
                           "Robert Jamieson (Church of Scotland, Presbyterian), A. R. Fausset (Church of Ireland, "
                           "Anglican) and David Brown (Free Church of Scotland, Presbyterian). Filed Tier 2 "
                           "Exegetes, labelled 'Presbyterian & Anglican' on every card -- broadly evangelical and "
                           "historically significant, but not itself a confessional-Reformed commentary and not "
                           "reviewed against the Westminster Confession. Covers all 66 books per the source's own "
                           "manifest."},
    },
    "mhcc": {
        "title": "Matthew Henry's Concise Commentary on the Bible",
        "short": "CCEL · Matthew Henry Concise",
        "publisher": "Christian Classics Ethereal Library (CCEL)",
        "url": "https://ccel.org/ccel/henry/mhcc.html",
        "license": "Public domain",
        "review": {"state": "source-attributed",
                   "note": "Restored 2026-09-23 (workstream E, 0.7 wave 2, E3) in a narrow, gap-only role: this "
                           "abridgment was retired 2026-09-22 in favor of Matthew Henry's unabridged Complete "
                           "Commentary ('matthew-henry' above), and is parsed again *only* for the specific "
                           "chapters where the Complete has zero entries -- see data/study-build-report.json for "
                           "the exact recomputed list. Everywhere the Complete has an entry, only the Complete "
                           "ships; this source never produces a second card next to a Complete entry for the "
                           "same verse. Not reviewed against the Westminster Confession."},
    },
    "calvin": {
        "title": "John Calvin's Commentaries (CrossWire CalvinCommentaries module)",
        "short": "CCEL · Calvin via Pillar data",
        "publisher": "CCEL / CrossWire; converted by the Pillar Commentary Data project (MIT)",
        "url": "https://ccel.org/ccel/calvin/calcom.html",
        "license": "Public domain text; MIT conversion",
        "review": {"state": "source-attributed",
                   "note": "Attributed to a Reformed author. Not reviewed against the Westminster Confession. "
                           "0.10 (workstream R2): for the Psalms this conversion carries, for 148 of 150 "
                           "chapters, ONE repeated block per psalm (the psalm's introduction + title comment + "
                           "the commentary on its first verse group) instead of per-verse commentary. 146 of "
                           "those chapters now ship HelloAO's per-verse Calvin text ('calvin-helloao') and keep "
                           "from this source only the psalm's own introduction paragraphs, which HelloAO's "
                           "digitization lacks, anchored at verse 1. Psalms 53 and 70 (where Calvin wrote no "
                           "separate commentary -- he refers the reader to Psalms 14 and 40) keep this source's "
                           "block. Psalms 55 and 120, where this conversion has genuine per-verse text, are "
                           "unchanged."},
    },
    "calvin-helloao": {
        "title": "John Calvin's Commentaries (HelloAO digitization, gap-fill: Isaiah 49–66 and the Psalms)",
        "short": "HelloAO · Calvin (Isaiah 49–66, Psalms)",
        "publisher": "Digitized by the HelloAO Free Use Bible API from the same public-domain Calvin "
                     "Translation Society English text as the app's primary Calvin source",
        "url": "https://bible.helloao.org/api/c/john-calvin/",
        "license": "Public Domain Mark 1.0",
        "review": {"state": "source-attributed",
                   "note": "Attributed to a Reformed author. Not reviewed against the Westminster Confession. "
                           "Gap-fill source, two scopes. (1) 2026-09-24 (workstream M, 0.9.5): the app's primary "
                           "'calvin' source (Pillar/CrossWire conversion) has empty content for Isaiah 49-66 -- "
                           "the entire Book of Consolation, including the Servant Songs and Isaiah 53 -- "
                           "confirmed as a genuine upstream gap (a fresh fetch of the same Pillar conversion is "
                           "also empty for these chapters), not a local corruption. HelloAO's independent "
                           "digitization of the same underlying commentary has real content for all 18 of these "
                           "chapters, verified against the Pillar copy's Isaiah 1 to be the same translation. "
                           "(2) 2026-09-24 (workstream R2, 0.10): the Psalms. The Pillar conversion repeats one "
                           "block per psalm under every verse for 148 of 150 chapters; HelloAO has the real "
                           "per-verse commentary (e.g. Ps 22:16 on 'they have pierced'), verified against the "
                           "Pillar text the two share (>= 90% of every chapter's shared 6-word shingles; see "
                           "data/study-build-report.json 'calvinPsalms'). Emitted only for ISA 49-66 and the PSA "
                           "chapters where Pillar has only the repeated block; in a given psalm this source's "
                           "per-verse text never sits beside a Pillar per-verse entry, and the only Pillar text "
                           "kept beside it is the psalm's introduction (absent from this digitization). The "
                           "translator's editorial footnotes (partly in French) and their inline [n] markers are "
                           "not shipped. See work-content/helloao/calvin-helloao/_fetch-manifest.json and "
                           "CONTENT-SOURCES.md."},
    },
    "hcf": {
        "title": "Historical Christian Faith Commentaries Database",
        "short": "Historical Christian Faith DB",
        "publisher": "Historical Christian Faith",
        "url": "https://github.com/HistoricalChristianFaith/Commentaries-Database",
        "license": "Mixed rights; individual editions require redistribution review",
        "review": {"state": "automated-filter",
                   "note": "Selected by an automated author whitelist. Not theologically reviewed; historical witness is not agreement with the Westminster Confession."},
    },
    "tsk": {
        "title": "Treasury of Scripture Knowledge cross-references (BSB versification)",
        "short": "TSK cross-references",
        "publisher": "CrossReferences.org",
        "url": "https://github.com/CrossReferences-org/bible-cross-references",
        "license": "CC BY 4.0",
        "review": {"state": "dataset-supplied",
                   "note": "Links supplied by the dataset; not reviewed and not a commentary."},
    },
}

TRADITION_ORDER = {"Fathers": 0, "Reformed": 1, "Exegetes": 2, "Cross-References": 3}


BOOKS = [
    ("GEN", "Genesis", "Gen", "genesis"), ("EXO", "Exodus", "Exod", "exodus"),
    ("LEV", "Leviticus", "Lev", "leviticus"), ("NUM", "Numbers", "Num", "numbers"),
    ("DEU", "Deuteronomy", "Deut", "deuteronomy"), ("JOS", "Joshua", "Josh", "joshua"),
    ("JDG", "Judges", "Judg", "judges"), ("RUT", "Ruth", "Ruth", "ruth"),
    ("1SA", "1 Samuel", "1 Sam", "1samuel"), ("2SA", "2 Samuel", "2 Sam", "2samuel"),
    ("1KI", "1 Kings", "1 Kgs", "1kings"), ("2KI", "2 Kings", "2 Kgs", "2kings"),
    ("1CH", "1 Chronicles", "1 Chr", "1chronicles"), ("2CH", "2 Chronicles", "2 Chr", "2chronicles"),
    ("EZR", "Ezra", "Ezra", "ezra"), ("NEH", "Nehemiah", "Neh", "nehemiah"),
    ("EST", "Esther", "Esth", "esther"), ("JOB", "Job", "Job", "job"),
    ("PSA", "Psalms", "Ps", "psalms"), ("PRO", "Proverbs", "Prov", "proverbs"),
    ("ECC", "Ecclesiastes", "Eccl", "ecclesiastes"), ("SNG", "Song of Solomon", "Song", "songofsolomon"),
    ("ISA", "Isaiah", "Isa", "isaiah"), ("JER", "Jeremiah", "Jer", "jeremiah"),
    ("LAM", "Lamentations", "Lam", "lamentations"), ("EZK", "Ezekiel", "Ezek", "ezekiel"),
    ("DAN", "Daniel", "Dan", "daniel"), ("HOS", "Hosea", "Hos", "hosea"),
    ("JOL", "Joel", "Joel", "joel"), ("AMO", "Amos", "Amos", "amos"),
    ("OBA", "Obadiah", "Obad", "obadiah"), ("JON", "Jonah", "Jonah", "jonah"),
    ("MIC", "Micah", "Mic", "micah"), ("NAM", "Nahum", "Nah", "nahum"),
    ("HAB", "Habakkuk", "Hab", "habakkuk"), ("ZEP", "Zephaniah", "Zeph", "zephaniah"),
    ("HAG", "Haggai", "Hag", "haggai"), ("ZEC", "Zechariah", "Zech", "zechariah"),
    ("MAL", "Malachi", "Mal", "malachi"), ("MAT", "Matthew", "Matt", "matthew"),
    ("MRK", "Mark", "Mark", "mark"), ("LUK", "Luke", "Luke", "luke"),
    ("JHN", "John", "John", "john"), ("ACT", "Acts", "Acts", "acts"),
    ("ROM", "Romans", "Rom", "romans"), ("1CO", "1 Corinthians", "1 Cor", "1corinthians"),
    ("2CO", "2 Corinthians", "2 Cor", "2corinthians"), ("GAL", "Galatians", "Gal", "galatians"),
    ("EPH", "Ephesians", "Eph", "ephesians"), ("PHP", "Philippians", "Phil", "philippians"),
    ("COL", "Colossians", "Col", "colossians"), ("1TH", "1 Thessalonians", "1 Thess", "1thessalonians"),
    ("2TH", "2 Thessalonians", "2 Thess", "2thessalonians"), ("1TI", "1 Timothy", "1 Tim", "1timothy"),
    ("2TI", "2 Timothy", "2 Tim", "2timothy"), ("TIT", "Titus", "Titus", "titus"),
    ("PHM", "Philemon", "Phlm", "philemon"), ("HEB", "Hebrews", "Heb", "hebrews"),
    ("JAS", "James", "Jas", "james"), ("1PE", "1 Peter", "1 Pet", "1peter"),
    ("2PE", "2 Peter", "2 Pet", "2peter"), ("1JN", "1 John", "1 John", "1john"),
    ("2JN", "2 John", "2 John", "2john"), ("3JN", "3 John", "3 John", "3john"),
    ("JUD", "Jude", "Jude", "jude"), ("REV", "Revelation", "Rev", "revelation"),
]

CODE_BY_CROSSREF = {abbr: code for code, _, abbr, _ in BOOKS}

# Longest-abbreviation-first so "1 Chr" matches before a looser partial would.
_REF_ABBR_ALTERNATION = "|".join(re.escape(a) for a in sorted(CODE_BY_CROSSREF, key=len, reverse=True))
REF_TOKEN = re.compile(rf"^({_REF_ABBR_ALTERNATION})\s+(\d+):([\d,\-]+)$")


def parse_ref_token(token: str) -> list[dict]:
    """"Prov 8:22-24" -> one link. "Ps 33:6,9" -> two. "Rev 12:17; Rev 13:1,3" -> semicolon-joined
    references to two different chapters -> parsed as two independent tokens."""
    if ";" in token:
        links = []
        for part in token.split(";"):
            links.extend(parse_ref_token(part))
        return links
    match = REF_TOKEN.match(token.strip())
    if not match:
        return []
    abbr, chapter_text, verses_text = match.groups()
    code = CODE_BY_CROSSREF[abbr]
    chapter = int(chapter_text)
    links = []
    for part in verses_text.split(","):
        span = re.fullmatch(r"(\d+)-(\d+)", part)
        if span:
            start, end = int(span[1]), int(span[2])
        elif part.isdigit():
            start = end = int(part)
        else:
            continue
        links.append({"code": code, "chapter": chapter, "start": start, "end": end, "label": f"{abbr} {chapter}:{part}"})
    return links
CODE_BY_NAME = {name: code for code, name, _, _ in BOOKS}
DB_BOOK = {code: slug for code, _, _, slug in BOOKS}

# ---------------------------------------------------------------- Fathers admission rule (0.8,
# workstream I)
#
# Through 0.7 this was a curated, deliberately narrow named list (17, then 21 names) because
# admitting "everyone the database doesn't happen to flag as condemned" would have misrepresented
# "not flagged" as "received." Matt's 0.8 brief changes the standard explicitly: "I don't want
# only reformed church fathers listed... I want the user to know the church fathers' theological
# bent." The new rule is admission by *category and era*, not a hand-picked list, with every
# admitted author now carrying a sourced theological profile (see fathers-profiles.json) so
# breadth doesn't cost the reader the ability to place a name theologically:
#
#   Default Fathers bank = every author the source database files under a patristic-era category
#   (Early Fathers (Pre-Nicaea), Eastern & Byzantine Theology, Syriac & Oriental Theology, or the
#   patristic part of Western & Medieval Theology) whose default_year (approximate death year) is
#   <= 800 -- "through c. AD 800" per the brief -- EXCEPT:
#     - persons condemned as a heretic/schismatic by a conciliar or synodal act (see
#       CONDEMNED_FATHERS below): they move to the existing Tier-3 opt-in toggle instead of being
#       dropped outright, each labelled with the specific council/synod + year a real source
#       documents (never a generic "condemned" with no citation);
#     - the Pseudonymous Works and Apocrypha/Pseudepigrapha/Early Documents categories (unchanged
#       from 0.5.2 -- these are not attributed authors at all).
#   Medieval Western scholastics (Aquinas, Bonaventure, Bernard of Clairvaux...) and modern
#   authors the database happens to also carry under Western & Medieval Theology or Eastern &
#   Byzantine Theology fall out of the bank naturally on the year cutoff (all > 800) -- Matt's
#   brief is explicit that these "are not church fathers," so no separate exclusion list is
#   needed for them the way FATHER_PRIORITY used to require.
#
#   The year cutoff is applied uniformly across all four categories, not just Western & Medieval:
#   verified directly against the database (2026-09-23), Eastern & Byzantine Theology and Syriac &
#   Oriental Theology both run centuries past 800 in this source (Photios I of Constantinople d.
#   893, Symeon the New Theologian d. 1022, Gregory Palamas d. 1359 under "Eastern & Byzantine";
#   Dionysius bar Salibi d. 1171, Nerses of Lambron d. 1198 under "Syriac & Oriental") -- these are
#   medieval/Byzantine theologians by any standard reckoning, not patristic fathers, and the same
#   "through c. AD 800" test correctly excludes them without a bespoke per-category rule.
#
# Two corrections to the database's own `condemned_by_council` flag were verified directly against
# Wace & Piercy's Dictionary of Christian Biography (1911) before shipping (see
# work-content/fathers-profiles.source.json for the citations) -- the brief's own instruction to
# "check the DB's condemned_by_council flag against a source before relying on it":
#   - Theodore of Mopsuestia: flagged 0 in this database, but was posthumously condemned, with
#     Theodoret's anti-Cyril writings and a letter of Ibas of Edessa, as one of the "Three
#     Chapters" at the Second Council of Constantinople (553, the Fifth Ecumenical Council).
#     Added to the condemned bucket despite the database's flag.
#   - Heracleon, Valentinus and Tatian the Assyrian: flagged 1 in this database (kept out of the
#     default bank on that basis, correctly), but neither DCB entry documents an ecumenical
#     council condemning any of the three *by name* -- all three predate the conciliar era
#     (2nd-century Gnostics and an Encratite) and were refuted by the Fathers' own writings
#     (chiefly Irenaeus), not a synodal act. Their profiles say this precisely -- no invented
#     "council + year" -- and `FatherProfile.conciliarJudgment` is `nil` for these three.
# A full scan for other historically well-known heresiarchs (Nestorius, Eutyches, Sabellius,
# Macedonius, Marcion, Montanus...) found none present in this database under any name, so no
# further override was needed.
PATRISTIC_CATEGORIES = (
    "Early Fathers (Pre-Nicaea)", "Eastern & Byzantine Theology",
    "Syriac & Oriental Theology", "Western & Medieval Theology",
)
PATRISTIC_YEAR_CUTOFF = 800
EXCLUDED_FATHER_CATEGORIES = ("Pseudonymous Works", "Apocrypha, Pseudepigrapha & Early Documents")
CONDEMNED_OVERRIDE_ADD = {"Theodore of Mopsuestia"}

# Priority order for the *default* bank's per-verse cap (see `max_per_verse` in `parse_fathers`):
# the long-established 21-name whitelist first (stable behavior for books this already covered),
# then the four the 0.8 brief explicitly named as moving into the default bank, then every other
# newly admitted author ranked by how much of the database their commentary actually occupies
# (row count) -- an objective, reproducible proxy for "how central a voice this is" where no
# editorial judgment call has been made, tie-broken alphabetically for determinism.
FATHER_PRIORITY = [
    "John Chrysostom", "Augustine of Hippo", "Athanasius of Alexandria", "Irenaeus",
    "Cyril of Alexandria", "Basil of Caesarea", "Gregory of Nazianzus", "Gregory of Nyssa",
    "Ambrose of Milan", "Jerome", "Cyril of Jerusalem", "Ephrem the Syrian", "Bede",
    "Clement of Rome", "Ignatius of Antioch", "Polycarp of Smyrna", "Justin Martyr",
    "Hilary of Poitiers", "Cyprian", "Hippolytus of Rome", "John Damascene",
    "Origen of Alexandria", "Tertullian", "Clement of Alexandria", "Eusebius of Caesarea",
]

# Condemned-bucket (Tier 3) priority order: the five carried over from 0.5.2-0.7 (Origen,
# Tertullian, Clement of Alexandria and Eusebius of Caesarea have since moved to the default bank
# per the 0.8 brief and are no longer here), then the newly computed heretics/schismatics ranked
# by row count.
CONDEMNED_PRIORITY = ["Theodore of Mopsuestia"]


def _father_admission() -> dict:
    """Queries the database once for every patristic-category author and sorts each into the
    default bank, the condemned (Tier 3) bucket, or excluded -- replacing the old hand-maintained
    name lists with the rule described above. Returns the raw rows too, so `main()` can report
    exact counts by category/reason without a second query."""
    database = WORK / "commentaries.sqlite"
    if not database.exists():
        return {"default": [], "condemned": [], "excludedLate": [], "rows": []}
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    placeholders = ",".join("?" for _ in PATRISTIC_CATEGORIES)
    rows = connection.execute(f"""
        SELECT m.name, m.default_year, m.father_category, m.condemned_by_council,
               COUNT(c.id) AS row_count
        FROM father_meta m LEFT JOIN commentary c ON c.father_name = m.name
        WHERE m.father_category IN ({placeholders})
        GROUP BY m.name
    """, PATRISTIC_CATEGORIES).fetchall()
    connection.close()

    default_names, condemned_names, excluded_late = [], [], []
    row_count = {}
    for row in rows:
        row_count[row["name"]] = row["row_count"]
        try:
            year = int(row["default_year"])
        except (TypeError, ValueError):
            year = None
        condemned = bool(row["condemned_by_council"]) or row["name"] in CONDEMNED_OVERRIDE_ADD
        if year is None or year > PATRISTIC_YEAR_CUTOFF:
            excluded_late.append(row["name"])
            continue
        (condemned_names if condemned else default_names).append(row["name"])

    def ranked(names: list[str], priority: list[str]) -> list[str]:
        rank = {name: index for index, name in enumerate(priority)}
        return sorted(names, key=lambda n: (rank.get(n, len(priority)), -row_count.get(n, 0), n))

    return {
        "default": ranked(default_names, FATHER_PRIORITY),
        "condemned": ranked(condemned_names, CONDEMNED_PRIORITY),
        "excludedLate": sorted(excluded_late),
        "rows": rows,
        "rowCount": row_count,
    }


_ADMISSION = _father_admission()
FATHER_RANK = {name: index for index, name in enumerate(_ADMISSION["default"])}
TIER3_RANK = {name: index for index, name in enumerate(_ADMISSION["condemned"])}



REPORT_DATA: dict = {"dropped": Counter(), "cleaned": Counter(), "notes": defaultdict(list)}


def note(kind: str, item) -> None:
    REPORT_DATA["notes"][kind].append(item)


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def make_entry(code, chapter, start, end, author, work, era, tradition, source, text,
               url=None, exact=True, basis="stated", truncated=False, cross_refs=None,
               tier="tier1", content_kind=None, author_tradition=None):
    text = clean(text)
    digest = hashlib.sha1("\x1f".join([author, work, text]).encode("utf-8")).hexdigest()[:8]
    if content_kind is None:
        content_kind = "verse-commentary" if int(end) == int(start) else "passage-commentary"
    item = {
        "id": f"{code}.{int(chapter)}.{int(start)}-{int(end)}.{source}.{digest}",
        "chapter": int(chapter), "startVerse": int(start), "endVerse": int(end),
        "rangeBasis": basis,
        "author": author, "work": work or "Commentary", "era": era,
        "tradition": tradition, "source": source, "excerpt": text,
        "isExactQuote": bool(exact),
        # Always present (even empty/default) so every entry decodes with the same Swift schema.
        "crossRefs": cross_refs or [],
        "tier": tier, "contentKind": content_kind,
        # Always present (nullable): the author's own confessional tradition, shown on every
        # Exegetes-bank card (E2, 0.7 wave 2) -- e.g. "Particular Baptist", "Lutheran". `None`
        # (JSON null) everywhere else.
        "authorTradition": author_tradition,
    }
    if url and url != SOURCES[source]["url"]:
        item["sourceURL"] = url
    if truncated:
        item["truncated"] = True
    return item


def classify_father_content_kind(work: str) -> str:
    """Heuristic, conservative content-kind for a patristic excerpt: defaults to the least
    specific claim (general-work) rather than overclaiming "commentary" for a genre the title
    doesn't actually support. Reviewed against the top ~40 `work` values by row count."""
    w = (work or "").lower()
    if re.search(r"\bhomil(y|ies)\b|\bsermon", w):
        return "sermon"
    if re.match(r"^letter\b", w):
        return "theological-discussion"
    if re.search(r"against heresies|treatise|testimonies against", w):
        return "theological-discussion"
    if re.search(r"commentary|commentaries|exposition|hexaemeron|catena|exegetical|hebrew questions|"
                 r"retractions|^on the (gospel|epistle)", w):
        return "passage-commentary"
    return "general-work"


# ---------------------------------------------------------------- Matthew Henry (retired 2026-09-22,
# restored gap-only 2026-09-23)
#
# The raw-text parser for Matthew Henry's Concise Commentary (work-content/mhcc.txt, CCEL) was
# retired 2026-09-22 in favor of the unabridged Complete Commentary via HelloAO (see
# parse_helloao_commentary below) -- two Henry cards per verse was clutter everywhere the
# Complete has an entry. Its one WCF candidate link (ROM.8.28-31.mhcc.9e98c639) was re-pointed to
# the equivalent matthew-henry entry, not deleted -- see Resources/Confession/wcf-links.json.
#
# Workstream E (0.7 wave 2, E3) restored this parser the next day in a deliberately narrow role:
# the Complete Commentary, verified directly against its own books.json and chapter files, has
# real gaps -- no Song of Solomon at all, 2 Samuel stops at 22 of 24, Jonah stops at 1 of 4,
# Matthew stops at 18 of 28 (missing the Passion narrative), plus isolated empty chapters within
# otherwise-complete books. `mhcc_gap_chapters()` below recomputes exactly which (code, chapter)
# pairs the Complete has zero entries for, from the Complete's own parsed output -- not a
# hardcoded list, so a future HelloAO update that fills a gap is picked up automatically and a
# regression that opens a new gap is caught automatically too. `parse_mhcc()` then parses the
# Concise *only* for those exact chapters, restoring both raw heading layouts the original
# 2026-09-21 parser (0.5.2) had to handle: a standalone "Verses N-M" line (every book below
# except the nine handled inline), and an inline "Song 1:2-6 The church confesses..." heading
# that folds the reference into the same line as the first sentence of commentary (Isaiah,
# Jeremiah, Ezekiel, Daniel, Hosea, Joel, Lamentations, Ecclesiastes, Song of Solomon).
MHCC_PATH = WORK / "mhcc.txt"
MHCC_INLINE_ABBR = {
    # This is CCEL's own in-text abbreviation for each book's inline heading, verified by direct
    # inspection of work-content/mhcc.txt -- it does not always match the TSK-derived `BOOKS`
    # abbreviation used elsewhere in this script (e.g. Isaiah is "Is." here, not "Isa"), so this
    # stays its own small table rather than reusing CODE_BY_CROSSREF.
    "ISA": "Is.", "JER": "Jer.", "EZK": "Ezek.", "DAN": "Dan.", "HOS": "Hos.",
    "JOL": "Joel", "LAM": "Lam.", "ECC": "Eccl.", "SNG": "Song",
}
MHCC_CHAPTER_HEADING = re.compile(r"^Chapter (\d+)$")
MHCC_VERSES_HEADING = re.compile(r"^Verses?\s+([\d,\-\s]+?)\s*$")
MHCC_DIVIDER = re.compile(r"^_{5,}$")


def mhcc_gap_chapters(henry: dict[str, list[dict]]) -> dict[str, set[int]]:
    """Every (code, chapter) the unabridged Matthew Henry Complete has zero entries for, among
    chapters that actually exist in the canon -- recomputed from `henry`'s own parsed output
    (not a hand-maintained list), per the workplan's "recompute exactly" instruction."""
    gaps: dict[str, set[int]] = {}
    for code, _, _, _ in BOOKS:
        counts = BSB_VERSE_COUNTS.get(code)
        if not counts:
            continue
        covered = {item["chapter"] for item in henry.get(code, [])}
        missing = {c for c in range(1, len(counts) + 1) if c not in covered}
        if missing:
            gaps[code] = missing
    return gaps


def _mhcc_verse_spec(spec: str) -> tuple[int, int]:
    """"1, 2" -> (1, 2); "3-5" -> (3, 5); "1" -> (1, 1); every number the heading names,
    min/max -- the same "the source itself states this range" convention the rest of the
    heading-driven parsers here use (rangeBasis "stated")."""
    numbers: list[int] = []
    for part in re.split(r"[,\s]+", spec.strip()):
        if not part:
            continue
        span = re.fullmatch(r"(\d+)-(\d+)", part)
        if span:
            numbers.extend([int(span[1]), int(span[2])])
        elif part.isdigit():
            numbers.append(int(part))
    if not numbers:
        return (0, 0)
    return (min(numbers), max(numbers))


# One isolated leftover RTF control word was found by a full-corpus scan of mhcc.txt while
# building the E3 gap-fill (2026-09-23): Matthew 26:26-30 (the Lord's Supper) has "...with
# you\rdblquote , may be understood..." -- a literal '\rdblquote' where a right double
# quotation mark belongs, evidently surviving an incomplete RTF-to-text conversion somewhere
# upstream of this raw file. Verified genuinely isolated (exactly one backslash in the entire
# 99,826-line file), so this is a narrow, specific fix, not a general escape-stripping
# heuristic -- the same "verify before generalizing" discipline as the Fathers backslash
# cleanup and the HelloAO emphasis-marker leak elsewhere in this script.
def _mhcc_fix_rtf_leak(text: str) -> str:
    if "\\rdblquote" not in text:
        return text
    REPORT_DATA["cleaned"]["mhcc: repaired a leftover RTF control word (\\rdblquote)"] += 1
    return text.replace("\\rdblquote", "”")


def _mhcc_join(body_lines: list[str]) -> str:
    kept = [line.strip() for line in body_lines if line.strip() and not MHCC_DIVIDER.match(line.strip())]
    return clean(_mhcc_fix_rtf_leak(" ".join(kept)))


def _parse_mhcc_standard(code: str, lines: list[str], wanted: set[int]) -> list[dict]:
    """The layout every book except the nine in MHCC_INLINE_ABBR uses: a bare "Chapter N" line,
    then (after a "Chapter Outline" summary this function simply never treats as a verse
    heading, since it never matches MHCC_VERSES_HEADING) a bare "Verses N-M" line per section,
    with the commentary paragraph(s) following until the next heading."""
    entries: list[dict] = []
    chapter: int | None = None
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if line[:1] not in (" ", "\t") and MHCC_CHAPTER_HEADING.match(stripped):
            chapter = int(MHCC_CHAPTER_HEADING.match(stripped)[1])
            i += 1
            continue
        heading = MHCC_VERSES_HEADING.match(stripped) if line[:1] not in (" ", "\t") and stripped else None
        if heading and chapter is not None:
            start_v, end_v = _mhcc_verse_spec(heading[1])
            i += 1
            body: list[str] = []
            while i < n:
                nxt = lines[i]
                nxt_stripped = nxt.strip()
                if nxt[:1] not in (" ", "\t") and (MHCC_CHAPTER_HEADING.match(nxt_stripped)
                                                    or (nxt_stripped and MHCC_VERSES_HEADING.match(nxt_stripped))):
                    break
                body.append(nxt)
                i += 1
            if chapter in wanted and start_v > 0:
                text = _mhcc_join(body)
                if len(text) >= 20:
                    entries.append(make_entry(
                        code, chapter, start_v, end_v, "Matthew Henry", "Concise Commentary",
                        "1662–1714", "Reformed", "mhcc", text, basis="stated", tier="tier1"))
            continue
        i += 1
    return entries


def _parse_mhcc_inline(code: str, lines: list[str], wanted: set[int]) -> list[dict]:
    """The nine books whose raw source folds the reference into the same line as the first
    sentence of commentary ("Song 1:2-6 The church, or rather the believer, speaks...") instead
    of a standalone heading line."""
    abbr = MHCC_INLINE_ABBR[code]
    heading = re.compile(rf"^\s*{re.escape(abbr)}\s+(\d+):([\d,\-]+)\s+(.*)$")
    positions = [(i, m) for i, line in enumerate(lines) if (m := heading.match(line))]
    entries: list[dict] = []
    for pos, (idx, m) in enumerate(positions):
        chapter = int(m[1])
        start_v, end_v = _mhcc_verse_spec(m[2])
        body_end = positions[pos + 1][0] if pos + 1 < len(positions) else len(lines)
        body = [m[3]] + lines[idx + 1:body_end]
        if chapter in wanted and start_v > 0:
            text = _mhcc_join(body)
            if len(text) >= 20:
                entries.append(make_entry(
                    code, chapter, start_v, end_v, "Matthew Henry", "Concise Commentary",
                    "1662–1714", "Reformed", "mhcc", text, basis="stated", tier="tier1"))
    return entries


def parse_mhcc(gap_chapters: dict[str, set[int]]) -> dict[str, list[dict]]:
    results: dict[str, list[dict]] = defaultdict(list)
    if not MHCC_PATH.exists() or not gap_chapters:
        return results
    lines = MHCC_PATH.read_text(encoding="utf-8", errors="replace").splitlines()
    # Book sections appear in the same canonical order as BOOKS, so a forward-only scan finds
    # each heading exactly once, unambiguously, even though some book names could in principle
    # recur elsewhere in the running text (front matter, cross-references).
    spans: dict[str, tuple[int, int]] = {}
    positions: list[tuple[str, int]] = []
    search_from = 0
    for code, name, _, _ in BOOKS:
        pattern = re.compile(rf"^\s+{re.escape(name)}\s*$")
        found = next((i for i in range(search_from, len(lines)) if pattern.match(lines[i])), None)
        if found is None:
            continue
        positions.append((code, found))
        search_from = found + 1
    for idx, (code, start) in enumerate(positions):
        end = positions[idx + 1][1] if idx + 1 < len(positions) else len(lines)
        spans[code] = (start, end)
    for code, wanted in gap_chapters.items():
        if code not in spans or not wanted:
            continue
        book_lines = lines[spans[code][0]:spans[code][1]]
        if code in MHCC_INLINE_ABBR:
            results[code].extend(_parse_mhcc_inline(code, book_lines, wanted))
        else:
            results[code].extend(_parse_mhcc_standard(code, book_lines, wanted))
    return results


# ---------------------------------------------------------------- HelloAO commentaries (Gill, Henry Complete)
#
# Shared parser for the HelloAO Free Use Bible API's commentary JSON (verified 2026-09-22:
# https://bible.helloao.org/api/available_commentaries.json, Public Domain Mark 1.0 for both
# john-gill and matthew-henry). Raw chapters are fetched once by
# scripts/fetch-helloao-commentaries.py into work-content/helloao/<id>/<BOOK>/<chapter>.json;
# this function only ever reads that local cache, so the build stays offline and reproducible.
#
# Chapter shape (inspected directly against Genesis 1, Psalm 119, Romans 8, Revelation 1,
# Isaiah 53 for both commentaries before writing this): {"chapter": {"number": N, "content": [
# {"type": "verse", "number": <start verse>, "content": ["<one long paragraph string>"]}, ...
# ]}}. There is no explicit end-of-range marker -- Gill is verse-by-verse (almost always one
# entry per verse) and Henry's Complete groups several verses under one discourse ("In these
# verses...") the way his Concise did, but neither states its own upper bound the way MHCC's
# "Verses N-M" headings did. The end is therefore inferred structurally: up to (but not
# including) the next entry's start verse, or the chapter's last real verse (from the bundled
# BSB manifest, read-only) for a chapter's final entry. rangeBasis is set honestly: "stated"
# when that inference lands on exactly one verse (the source's own per-verse structure), "block"
# when it spans more than one (the boundary is inferred, not itself asserted by the text).
MOJIBAKE_MARKERS = ("Ã", "â€", "Â")


def fix_mojibake(text: str) -> str:
    """The raw HelloAO Gill/Henry JSON occasionally double-encodes non-ASCII characters --
    verified directly: Genesis 1 (Gill) contains the byte sequence for 'Elohim\xc3\x83\xc2\xb6',
    which is 'ö' (UTF-8 C3 B6) reinterpreted as Latin-1 and re-encoded as UTF-8 a second time.
    Reverses exactly that transform, and only keeps the result if it actually reduces the
    mojibake-marker count, so ordinary ASCII text (the overwhelming majority) is never touched."""
    if not any(marker in text for marker in MOJIBAKE_MARKERS):
        return text
    try:
        candidate = text.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text
    before = sum(text.count(m) for m in MOJIBAKE_MARKERS)
    after = sum(candidate.count(m) for m in MOJIBAKE_MARKERS)
    if after < before:
        REPORT_DATA["cleaned"]["helloao: repaired double-encoded UTF-8 (mojibake)"] += 1
        return candidate
    return text


def load_bsb_verse_counts() -> dict[str, list[int]]:
    """Chapter lengths (real verses, superscriptions excluded) from the already-bundled BSB
    Scripture pack manifest -- read-only, used only to infer where a commentary's final entry
    in a chapter ends, since HelloAO gives no explicit upper bound."""
    manifest_path = ROOT / "Sources/StudyTable/Resources/Scripture/BSB/manifest.json"
    if not manifest_path.exists():
        return {}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    return {book["code"]: book["verses"] for book in manifest["books"]}


BSB_VERSE_COUNTS = load_bsb_verse_counts()
MARKUP_LEAK = re.compile(r"[<{]|\\")
# One isolated literal '\@@...\@@' emphasis-marker leak was found in the entire corpus (both
# commentaries, all 2,356 chapter files scanned directly): John Gill on Luke 23:43 (the dying
# thief). Confirmed not systemic -- stripped rather than dropping otherwise-good commentary on
# a well-known passage, unlike the generic MARKUP_LEAK check below, which still drops anything
# else that leaks '<', '{' or a stray backslash, since those were never observed and a future
# occurrence should be reported, not silently repaired by a pattern tuned to this one case.
HELLOAO_EMPHASIS_LEAK = re.compile(r"\\@@")


def strip_emphasis_leak(text: str) -> str:
    if "\\@@" not in text:
        return text
    REPORT_DATA["cleaned"]["helloao: stripped literal emphasis-marker leak (\\@@)"] += 1
    return HELLOAO_EMPHASIS_LEAK.sub("", text)


def parse_helloao_commentary(source_id: str, author: str, default_work: str, era: str,
                              tradition: str = "Reformed", tier: str = "tier1",
                              author_tradition: str | None = None,
                              books: set[str] | None = None, text_filter=None) -> dict[str, list[dict]]:
    """`books` restricts the parse to those book codes (used by the narrow `calvin-helloao` gap-fill,
    whose directory also holds Psalms files that need the dedicated parser below); `text_filter`, if
    given, is applied to each entry's raw text before cleaning (see strip_calvin_helloao_apparatus)."""
    base = HELLOAO / source_id
    results = defaultdict(list)
    if not base.exists():
        return results
    for code, _, _, _ in BOOKS:
        if books is not None and code not in books:
            continue
        book_dir = base / code
        if not book_dir.exists():
            continue  # e.g. matthew-henry has no Song of Solomon -- see SOURCES note above.
        chapter_paths = sorted(book_dir.glob("*.json"), key=lambda p: int(p.stem))
        for path in chapter_paths:
            chapter = int(path.stem)
            data = json.loads(path.read_text(encoding="utf-8"))
            verse_items = sorted(
                (item for item in data.get("chapter", {}).get("content", [])
                 if item.get("type") == "verse" and item.get("number")),
                key=lambda item: item["number"],
            )
            counts = BSB_VERSE_COUNTS.get(code)
            chapter_max = counts[chapter - 1] if counts and 1 <= chapter <= len(counts) else None
            for i, item in enumerate(verse_items):
                start = int(item["number"])
                raw = " ".join(p for p in (item.get("content") or []) if isinstance(p, str))
                if text_filter is not None:
                    raw = text_filter(raw, f"{code} {chapter}:{start}")
                text = fix_mojibake(clean(strip_emphasis_leak(raw)))
                if len(text) < 20:
                    if text:
                        REPORT_DATA["dropped"][f"{source_id}: empty after cleaning"] += 1
                    continue
                if MARKUP_LEAK.search(text):
                    REPORT_DATA["dropped"][f"{source_id}: markup leakage (<, {{ or \\)"] += 1
                    note(f"{source_id}: markup leakage, entry dropped", f"{code} {chapter}:{start}")
                    continue
                if i + 1 < len(verse_items):
                    end = int(verse_items[i + 1]["number"]) - 1
                else:
                    end = chapter_max if chapter_max and chapter_max >= start else start
                if end < start:
                    REPORT_DATA["cleaned"][f"{source_id}: inferred end before start, kept at single verse"] += 1
                    note(f"{source_id}: two entries anchored at the same verse (kept both, second at single verse)",
                         f"{code} {chapter}:{start}")
                    end = start
                basis = "stated" if end == start else "block"
                results[code].append(make_entry(
                    code, chapter, start, end, author, default_work, era, tradition, source_id, text,
                    basis=basis, tier=tier, author_tradition=author_tradition))
    return results


# ---------------------------------------------------------------- Calvin on the Psalms (0.10, R2)
#
# The problem (found by the 0.10 pastor QA, confirmed against the raw data by R2): the Pillar/
# CrossWire Calvin conversion has, for 148 of the 150 psalm chapters, ONE text repeated in every
# verse slot -- the psalm's own introduction and title comment, followed by only the commentary on
# the psalm's FIRST verse group. parse_calvin() correctly collapses that to one "block" card, but a
# block spanning the whole psalm shows under every verse (Ps 22 = one 2,240-word card that never
# mentions "pierced", the word Calvin spends most of Ps 22:16 on). Psalms 55 and 120 are the only
# chapters where Pillar carries genuine per-verse text.
#
# HelloAO's independent digitization of the same Calvin Translation Society English text
# (work-content/helloao/calvin-helloao/PSA/1..150.json, fetched with
# `fetch-helloao-commentaries.py john-calvin --books PSA --dest-id calvin-helloao`) has the real
# per-verse commentary for all 150 chapters, organised as verse groups. Each group item is:
#     "Psalm 22:12-16"                          <- header, states the group's verse range
#     [optional inscription line, e.g. "A Psalm of David."]
#     "12. Strong bulls ... 16. For dogs ..."   <- Calvin's own rendering of those verses (quoted text)
#     "12. Strong bulls have encompassed me. The Psalmist now ..."   <- commentary, one or more
#     "14. I am poured out like water. Hitherto ..."                    paragraphs per verse, each
#     "16. They have pierced my hands and my feet. The original ..."    opening with its verse number
#     "Footnotes:" + "[n] ..." paragraphs      <- the translator's editorial notes (partly French)
#
# PRECEDENCE RULE (documented, tested):
#   1. Psalm chapters where Pillar has genuine per-verse text (not a single repeated block) keep
#      Pillar exactly as before and HelloAO is not used (Ps 55, Ps 120).
#   2. Chapters where Pillar has only the repeated block ship HelloAO's per-verse commentary INSTEAD,
#      split at each verse-numbered paragraph, so a verse's card starts where Calvin's own text
#      starts on that verse. Pillar's block is dropped -- except...
#   3. ...the psalm's introduction (the prefix of Pillar's block before the first "Psalm N:a-b"
#      group header, i.e. the argument of the psalm and Calvin's comment on its title), which
#      HelloAO's digitization does not carry, is kept as ONE Pillar-sourced entry anchored at verse 1
#      (never repeated across the psalm). This is the only case where a chapter carries Calvin from
#      both sources, and the two texts are disjoint by construction (checked: the introduction's
#      word-shingles must not appear in the HelloAO chapter, else it is dropped as a duplicate).
#   4. Safe fallbacks: if HelloAO's chapter is missing/unparseable, or the Pillar block's text is not
#      found in HelloAO's chapter (the same-translation check below fails), Pillar's block is kept
#      and HelloAO is not used for that chapter.
#
# SAME-TRANSLATION CHECK (a hard gate, per chapter): the Pillar block after the introduction is
# Calvin's rendering + comment on the first verse group -- the very text HelloAO's first group
# contains. The fraction of its 6-word shingles that occur in HelloAO's chapter must be >= 0.90;
# measured across all 148 chapters and recorded in data/study-build-report.json ('calvinPsalms').
# Nothing here writes, rewrites or paraphrases a word of Calvin: text is only ever selected,
# split at paragraph boundaries, or removed (apparatus below), and every removal is counted.
#
# Apparatus NOT shipped (counted in the report): the "Footnotes:" section (the CTS translator's
# editorial notes, several in French) and the inline "[n]" markers pointing at it (with the notes
# gone they'd dangle), the header line, the inscription line and the quoted rendering of the verse
# group (the app shows the Scripture itself; each commentary paragraph opens with the verse and
# its rendered clause). The raw files keep all of it.
CALVIN_FOOTNOTES_TAIL = "\n\nFootnotes:"
CALVIN_FOOTNOTE_MARKER = re.compile(r"([ \t]*)\[\d{1,4}\]([ \t]*)(?=(.?))")


def _drop_footnote_marker(match: re.Match) -> str:
    """Replace one "[n]" marker: keep exactly one space when it sat between two words (so
    "in the [9]sixty-fifth" never fuses into "thesixty"), none when it hugged punctuation."""
    before, after, following = match.groups()
    if following and following in ",.;:!?)”’'\"":
        return ""
    return " " if (before or after) else ""
PSALM_GROUP_HEADER = re.compile(r"^Psalm (\d+):(\d+)(?:-(\d+))?$")
# The rendering paragraph opens with the group's first verse number, sometimes preceded by the
# transliterated Hebrew acrostic letter of Psalm 119 ("v 9.", "ch 57.", "' 1.").
PSALM_RENDERING_LEAD = re.compile(r"^[^\d]{0,4}?\s*(\d{1,3})\.")
# A commentary paragraph opens with its verse number, with or without a period ("1. Blessed is the
# man." / "12 The righteous shall flourish"); the guard rejects a paragraph that merely begins with
# a numbered book ("1 Corinthians 15:..").
PSALM_COMMENTARY_LEAD = re.compile(r"^(\d{1,3})\.?\s+(?=\S)")
PSALM_NUMBERED_BOOK = re.compile(
    r"^\d{1,3}\.?\s+(?:Samuel|Sam\b|Kings|Kgs\b|Chronicles|Chron\b|Chr\b|Corinthians|Cor\b|"
    r"Thessalonians|Thess\b|Timothy|Tim\b|Peter|Pet\b|John\b)")
# One verified upstream misfiling in HelloAO's Psalms: the group for Psalm 104:19-22 (the moon that
# marks the seasons, the lions that roar after their prey) sits, header mislabelled "Psalm 102:19-22"
# and glued to the preceding text, inside Psalm 102's own item 19 -- after that item's footnotes --
# while Psalm 104's file has no group covering verses 19-23 at all (gap 18 -> 24). Verified by
# reading the raw text (its quoted verses are Psalm 104:19-22, not 102:19-22, whose own group opens
# "For he hath looked down from the high place of his holiness"). Re-homed here, text untouched: only
# the locator header is rewritten. Applied only if the destination chapter really has no group at
# that verse, so a corrected upstream file would simply stop triggering it.
HELLOAO_PSA_MISFILED = [
    {"file_chapter": 102, "item": 19, "glued_header": "Psalm 102:19-22", "true_chapter": 104,
     "true_header": "Psalm 104:19-22", "start": 19},
]
PSALMS_MIN_SAME_TRANSLATION_COVERAGE = 0.90
PSALMS_INTRO_MAX_DUPLICATE_SHARE = 0.50
CALVIN_ERA = "1509–1564"
PSALM_INTRO_WORK = "Commentary (introduction to the psalm)"


def strip_calvin_helloao_apparatus(raw: str, where: str = "", count: bool = True) -> str:
    """Remove the translator's footnote section and the inline "[n]" markers that point at it from
    one HelloAO Calvin item. Applied to both the Isaiah 49-66 gap-fill and the Psalms, so the two
    scopes of the `calvin-helloao` source read identically (0.9.5 shipped Isaiah with 488 dangling
    markers and 18 leaked "Footnotes:" sections; this pass removes them there too)."""
    if CALVIN_FOOTNOTES_TAIL in raw:
        head, tail = raw.split(CALVIN_FOOTNOTES_TAIL, 1)
        known_misfile = any(where == f"PSA {f['file_chapter']}:{f['item']}" for f in HELLOAO_PSA_MISFILED)
        odd = [p for p in tail.split("\n\n")
               if p.strip() and p.strip() != "Footnotes:" and not re.match(r"^\[\d{1,4}\]", p.strip())]
        if odd and count and not known_misfile:
            # Not observed in the current data; if a future fetch changes that, surface it rather than
            # silently swallow what might be commentary.
            note("calvin-helloao: text after 'Footnotes:' that is not a numbered footnote (removed with it)",
                 f"{where}: {odd[0][:80]!r}")
        if count:
            REPORT_DATA["cleaned"]["calvin-helloao: translator's footnotes section removed"] += 1
        raw = head
    markers = len(CALVIN_FOOTNOTE_MARKER.findall(raw))
    if markers:
        if count:
            REPORT_DATA["cleaned"]["calvin-helloao: inline footnote markers [n] removed"] += markers
        raw = CALVIN_FOOTNOTE_MARKER.sub(_drop_footnote_marker, raw)
    return raw


def _calvin_shingles(text: str, n: int = 6) -> set[tuple[str, ...]]:
    text = re.sub(r"\[\d{1,4}\]", " ", text)
    words = re.findall(r"[a-z]+", text.lower())
    return {tuple(words[i:i + n]) for i in range(len(words) - n + 1)}


def parse_calvin_psalm_group(chapter: int, item: dict) -> dict | None:
    """One HelloAO group item -> {"start","end","pieces":[(verse, text)...], "lead": [text...]}, or None
    if the item does not have the documented shape (reported, never guessed at)."""
    raw = " ".join(p for p in (item.get("content") or []) if isinstance(p, str))
    where = f"PSA {chapter}:{item.get('number')}"
    text = strip_calvin_helloao_apparatus(strip_emphasis_leak(raw), where)
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return None
    header = PSALM_GROUP_HEADER.match(paragraphs[0])
    if not header or int(header.group(1)) != chapter:
        note("calvin-helloao PSA: group without a 'Psalm N:a-b' header (chapter kept from Pillar)", where)
        return None
    start = int(header.group(2))
    end = int(header.group(3) or start)
    if start != int(item.get("number") or start):
        note("calvin-helloao PSA: header start disagrees with item number (chapter kept from Pillar)", where)
        return None
    # Locate the quoted rendering: the first paragraph (after at most one inscription line) that opens
    # with this group's first verse number. Everything after it is commentary.
    index = 1
    if index < len(paragraphs) and not PSALM_RENDERING_LEAD.match(paragraphs[index]) \
            and len(paragraphs[index]) < 120 and not re.match(r"^\d", paragraphs[index]):
        REPORT_DATA["cleaned"]["calvin-helloao PSA: inscription line (psalm title) dropped"] += 1
        index += 1
    rendering = PSALM_RENDERING_LEAD.match(paragraphs[index]) if index < len(paragraphs) else None
    if not rendering or int(rendering.group(1)) != start:
        note("calvin-helloao PSA: quoted rendering not found after the group header (chapter kept from Pillar)",
             where)
        return None
    REPORT_DATA["cleaned"]["calvin-helloao PSA: group header + quoted rendering dropped (not commentary)"] += 1
    commentary = paragraphs[index + 1:]
    lead: list[str] = []
    pieces: list[tuple[int, list[str]]] = []
    for paragraph in commentary:
        m = PSALM_COMMENTARY_LEAD.match(paragraph)
        if m and not PSALM_NUMBERED_BOOK.match(paragraph):
            verse = int(m.group(1))
            previous = pieces[-1][0] if pieces else start - 1
            chapter_max = (BSB_VERSE_COUNTS.get("PSA") or [0] * 150)[chapter - 1] or 10 ** 6
            if previous < verse <= chapter_max and verse >= start:
                pieces.append((verse, [paragraph]))
                continue
        if pieces:
            pieces[-1][1].append(paragraph)
        else:
            lead.append(paragraph)
    return {"start": start, "end": end, "lead": lead, "pieces": pieces}


def rehome_misfiled_psalm_groups() -> dict[int, list[dict]]:
    """Synthesize HelloAO-shaped items for groups filed under the wrong psalm (HELLOAO_PSA_MISFILED)."""
    rehomed: dict[int, list[dict]] = defaultdict(list)
    for fix in HELLOAO_PSA_MISFILED:
        source = HELLOAO / "calvin-helloao" / "PSA" / f"{fix['file_chapter']}.json"
        target = HELLOAO / "calvin-helloao" / "PSA" / f"{fix['true_chapter']}.json"
        if not source.exists() or not target.exists():
            continue
        items = json.loads(source.read_text(encoding="utf-8"))["chapter"]["content"]
        item = next((i for i in items if i.get("number") == fix["item"]), None)
        if item is None:
            continue
        raw = " ".join(p for p in item["content"] if isinstance(p, str))
        glued = "\n\n" + fix["glued_header"]
        # The glued header is followed directly by the next paragraph's opening ("...22" + "19. He hath").
        position = raw.find(glued, raw.find(CALVIN_FOOTNOTES_TAIL))
        if position < 0:
            continue
        target_items = json.loads(target.read_text(encoding="utf-8"))["chapter"]["content"]
        if any(i.get("number") == fix["start"] for i in target_items):
            continue  # upstream fixed it: nothing to re-home
        paragraphs = raw[position + 2:].split("\n\n")
        paragraphs[0] = paragraphs[0][len(fix["glued_header"]):].lstrip()
        synthetic = fix["true_header"] + "\n\n" + "\n\n".join(paragraphs)
        rehomed[fix["true_chapter"]].append({"type": "verse", "number": fix["start"], "content": [synthetic]})
        REPORT_DATA["cleaned"]["calvin-helloao PSA: re-homed a misfiled group (Ps 102 item 19 -> Ps 104:19-22)"] += 1
        note("calvin-helloao PSA: group found under the wrong psalm and re-homed (text untouched, locator only)",
             f"{fix['glued_header']} (in Psalm {fix['file_chapter']}'s file) -> {fix['true_header']}")
    return rehomed


def build_calvin_psalms(pillar_entries: list[dict]) -> dict:
    """Apply the Psalms precedence rule (see the block comment above). `pillar_entries` is the Calvin
    list parse_calvin() produced for PSA. Returns the Pillar entries to keep, the HelloAO per-verse
    entries, the intro entries, and the exact per-chapter accounting for the build report."""
    base = HELLOAO / "calvin-helloao" / "PSA"
    counts = BSB_VERSE_COUNTS.get("PSA") or []
    by_chapter: dict[int, list[dict]] = defaultdict(list)
    for entry in pillar_entries:
        by_chapter[entry["chapter"]].append(entry)

    kept_pillar: list[dict] = []
    helloao: list[dict] = []
    intros: list[dict] = []
    rehomed = rehome_misfiled_psalm_groups()
    report = {
        "chaptersImproved": [], "chaptersKeptPillarPerVerse": [], "chaptersFallbackToPillarBlock": {},
        "introEntries": 0, "chaptersWithoutIntro": [], "sameTranslationCoverage": {},
        "introDuplicateShareMax": 0.0, "helloaoEntries": 0, "helloaoEntriesByBasis": Counter(),
        "perChapterEntries": {},
    }
    for chapter in sorted(by_chapter):
        entries = by_chapter[chapter]
        block_only = len(entries) == 1 and entries[0]["rangeBasis"] == "block"
        if not block_only:
            kept_pillar.extend(entries)
            report["chaptersKeptPillarPerVerse"].append(chapter)
            continue
        path = base / f"{chapter}.json"
        groups = None
        reason = None
        if not path.exists():
            reason = "no HelloAO chapter file"
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
            items = sorted([i for i in data.get("chapter", {}).get("content", [])
                            if i.get("type") == "verse" and i.get("number")] + rehomed.get(chapter, []),
                           key=lambda i: i["number"])
            parsed = [parse_calvin_psalm_group(chapter, i) for i in items]
            if not items:
                reason = "HelloAO chapter has no groups"
            elif any(g is None for g in parsed):
                reason = "HelloAO chapter has an unparseable group"
            elif not any(g["pieces"] or g["lead"] for g in parsed):
                reason = "HelloAO carries no commentary text for this psalm (only the quoted psalm)"
            else:
                groups = parsed
        block_text = entries[0]["excerpt"]
        intro_text = None
        if groups is not None:
            first = groups[0]
            # The header, then (at most) an inscription line and the acrostic letter, then the rendering's
            # opening verse number.
            header_re = re.compile(
                rf"Psalm {chapter}:{first['start']}(?:-{first['end']})?\s+(?:\[\d{{1,4}}\]|[^\d]){{0,140}}?{first['start']}\.")
            match = header_re.search(block_text)
            if not match:
                reason = "Pillar block does not contain the first HelloAO group header"
                groups = None
            else:
                hello_shingles: set = set()
                for i in items:
                    hello_shingles |= _calvin_shingles(
                        strip_calvin_helloao_apparatus(" ".join(x for x in i["content"] if isinstance(x, str)), "", count=False))
                shared = _calvin_shingles(block_text[match.start():])
                coverage = len(shared & hello_shingles) / len(shared) if shared else 0.0
                report["sameTranslationCoverage"][chapter] = round(coverage, 4)
                if coverage < PSALMS_MIN_SAME_TRANSLATION_COVERAGE:
                    reason = f"same-translation check failed (coverage {coverage:.2f})"
                    groups = None
                else:
                    prefix = clean(block_text[:match.start()])
                    prefix = re.sub(r"^Commentary upon the book of Psalms\s+", "", prefix)
                    if len(prefix) >= 40:
                        own = _calvin_shingles(prefix)
                        duplicate = len(own & hello_shingles) / len(own) if own else 0.0
                        report["introDuplicateShareMax"] = max(report["introDuplicateShareMax"], round(duplicate, 4))
                        if duplicate <= PSALMS_INTRO_MAX_DUPLICATE_SHARE:
                            intro_text = prefix
        if groups is None:
            kept_pillar.extend(entries)
            report["chaptersFallbackToPillarBlock"][str(chapter)] = reason
            note("calvin PSA: kept the Pillar block (HelloAO per-verse text not used)", f"PSA {chapter}: {reason}")
            continue

        chapter_max = counts[chapter - 1] if 1 <= chapter <= len(counts) else None
        chapter_entries: list[dict] = []
        for gi, group in enumerate(groups):
            is_last_group = gi == len(groups) - 1
            starts: list[tuple[int, list[str]]] = []
            lead_texts = group["lead"]
            pieces = group["pieces"]
            if not pieces:
                starts.append((group["start"], lead_texts))
            else:
                if lead_texts:
                    if pieces[0][0] == group["start"]:
                        pieces[0] = (pieces[0][0], lead_texts + pieces[0][1])
                    else:
                        starts.append((group["start"], lead_texts))
                starts.extend(pieces)
            group_end = max(group["end"], starts[-1][0])
            if is_last_group and chapter_max and chapter_max > group_end:
                # Same convention as parse_helloao_commentary(): the chapter's final entry runs to the
                # chapter's last verse (the header of a psalm's last group is sometimes short of it --
                # Ps 7, 13, 84, 92 -- while the commentary goes on to the closing verse).
                group_end = chapter_max
            for i, (verse, texts) in enumerate(starts):
                end = starts[i + 1][0] - 1 if i + 1 < len(starts) else group_end
                if chapter_max:
                    end = min(end, chapter_max)
                    if verse > chapter_max:
                        REPORT_DATA["dropped"]["calvin-helloao PSA: entry beyond the chapter's last verse"] += 1
                        continue
                end = max(end, verse)
                text = fix_mojibake(clean(" ".join(texts)))
                if len(text) < 20:
                    REPORT_DATA["dropped"]["calvin-helloao PSA: empty after cleaning"] += 1
                    continue
                if MARKUP_LEAK.search(text):
                    REPORT_DATA["dropped"]["calvin-helloao: markup leakage (<, { or \\)"] += 1
                    note("calvin-helloao: markup leakage, entry dropped", f"PSA {chapter}:{verse}")
                    continue
                basis = "stated" if end == verse else "block"
                chapter_entries.append(make_entry(
                    "PSA", chapter, verse, end, "John Calvin", "Commentary", CALVIN_ERA, "Reformed",
                    "calvin-helloao", text, basis=basis, tier="tier1"))
        helloao.extend(chapter_entries)
        report["chaptersImproved"].append(chapter)
        report["perChapterEntries"][str(chapter)] = len(chapter_entries)
        for entry in chapter_entries:
            report["helloaoEntriesByBasis"][entry["rangeBasis"]] += 1
        if intro_text:
            # One entry, at verse 1 only: never repeated across the psalm (the bug being fixed).
            intros.append(make_entry(
                "PSA", chapter, 1, 1, "John Calvin", PSALM_INTRO_WORK, CALVIN_ERA,
                "Reformed", "calvin", intro_text, basis="anchored", tier="tier1",
                content_kind="passage-commentary"))
        else:
            report["chaptersWithoutIntro"].append(chapter)
    report["introEntries"] = len(intros)
    report["helloaoEntries"] = len(helloao)
    report["helloaoEntriesByBasis"] = dict(report["helloaoEntriesByBasis"])
    return {"pillar": kept_pillar, "helloao": helloao, "intros": intros, "report": report}


# ---------------------------------------------------------------- Cross-references

def parse_crossrefs() -> dict[str, list[dict]]:
    grouped = defaultdict(lambda: defaultdict(lambda: {"anchors": [], "refs": []}))
    with (WORK / "crossreferences_bsb.tsv").open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            code = CODE_BY_CROSSREF.get(row["book"])
            if not code:
                REPORT_DATA["dropped"]["xref: unknown book abbreviation"] += 1
                continue
            target = grouped[code][(int(row["chapter"]), int(row["verse"]))]
            if row["anchor"] and row["anchor"] not in target["anchors"]:
                target["anchors"].append(row["anchor"])
            for ref in row["references"].split("|"):
                if ref and ref not in target["refs"]:
                    target["refs"].append(ref)
    results = defaultdict(list)
    for code, verses in grouped.items():
        for (chapter, verse), data in verses.items():
            refs = data["refs"][:28]
            truncated = len(data["refs"]) > 28
            if truncated:
                REPORT_DATA["cleaned"]["xref: link list capped at 28"] += 1
            anchors = ", ".join(data["anchors"][:5])
            text = " · ".join(refs)
            if anchors:
                text = f"Links for {anchors}: {text}"
            cross_refs = []
            for ref in refs:
                parsed = parse_ref_token(ref)
                if not parsed:
                    REPORT_DATA["dropped"]["xref: reference token did not parse (kept in display text)"] += 1
                cross_refs.extend(parsed)
            results[code].append(make_entry(
                code, chapter, verse, verse, "Scripture interprets Scripture",
                "Treasury of Scripture Knowledge links", "Canonical index", "Cross-References",
                "tsk", text, exact=False, truncated=truncated, cross_refs=cross_refs,
                tier="tier1", content_kind="canonical-index"))
    return results


# ---------------------------------------------------------------- Calvin

# The Pillar conversion inherits three defects from the CrossWire module, which this
# cleaner removes and reports (see data/study-build-report.json):
#   1. the last verse slot of a book or chapter carries the next book's title page /
#      preface, or the next chapter's heading and opening text,
#   2. some chapters repeat one whole-chapter block in every verse slot,
#   3. a slot's verse number can be a dropped-digit typo (e.g. Gen 31:22 filed as 31:2).
CALVIN_TAIL = re.compile(
    r"(END OF (?:THE |THIS )?[A-Z]{4,}|end of the (?:first|second|third) epistle|"
    r"THE AUTHOR’S DEDICATORY EPISTLE|PRELECTIONS OF JOHN CALVIN|A TRANSLATION OF CALVIN’S VERSION|"
    r"COMMENTAR(?:Y|IES) ON THE [A-Z]|THE ARGUMENT\b|"
    r"CHAPTER \d+\s+(?:[1-3]\s+)?[A-Z][A-Za-z ]+ \d+:\d+)"
)
CALVIN_BLOCK_HEADER = re.compile(
    r"^(?:COMMENTARIES ON [A-Z’' ,.]+?\s+)?CHAPTER \d+\s+(?:[1-3]\s+)?[A-Z][A-Za-z ]+ \d+:\d+(?:-\d+)?(?:,\s*\d+)?\s+"
)
CALVIN_MARKER = re.compile(r"^(?:(\d+):)?(\d+)(?:\s*[-–—]\s*(\d+))?\s*\.")


def flatten_calvin_content(nodes) -> str:
    pieces: list[str] = []

    def walk(value):
        if isinstance(value, dict):
            if isinstance(value.get("text"), str):
                pieces.append(value["text"])
            for key, child in value.items():
                if key != "text":
                    walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(nodes)
    return clean(" ".join(pieces))


def clean_calvin_text(text: str) -> str:
    match = CALVIN_TAIL.search(text)
    if match and match.start() > 0:
        REPORT_DATA["cleaned"]["calvin: trailing next-book/next-chapter matter removed"] += 1
        text = text[: match.start()].rstrip()
    # Isolated case, verified directly against the raw Pillar JSON (not a parsing artifact):
    # Jer 1:5 has a genuine editorial cross-reference aside, "{see Hebrews 5:4}", using curly
    # braces where every other Calvin entry in the corpus (checked: only this one pair exists)
    # uses none. Normalized to parentheses so it reads as prose, not as leaked markup.
    if "{" in text or "}" in text:
        REPORT_DATA["cleaned"]["calvin: normalized a curly-brace editorial aside to parentheses"] += 1
        text = text.replace("{", "(").replace("}", ")")
    return text


def parse_calvin() -> dict[str, list[dict]]:
    results = defaultdict(list)
    if not CALVIN.exists():
        return results
    for code, _, _, _ in BOOKS:
        directory = CALVIN / code
        if not directory.exists():
            continue
        for path in sorted(directory.glob("*.json"), key=lambda p: int(p.stem)):
            chapter = int(path.stem)
            data = json.loads(path.read_text(encoding="utf-8"))
            slots: list[tuple[int, str]] = []
            for item in data.get("chapter", {}).get("content", []):
                if item.get("type") != "verse" or not item.get("number"):
                    continue
                text = clean_calvin_text(flatten_calvin_content(item.get("content", [])))
                if len(text) < 20:
                    if text:
                        REPORT_DATA["dropped"]["calvin: empty after cleaning"] += 1
                    continue
                slots.append((int(item["number"]), text))

            by_text: dict[str, list[int]] = defaultdict(list)
            for slot, text in slots:
                by_text[text].append(slot)

            emitted: set[str] = set()
            for slot, text in slots:
                if text in emitted:
                    continue
                emitted.add(text)
                verses = by_text[text]
                if len(verses) > 1:
                    body = CALVIN_BLOCK_HEADER.sub("", text, count=1)
                    REPORT_DATA["cleaned"]["calvin: repeated chapter block collapsed"] += 1
                    REPORT_DATA["dropped"]["calvin: duplicate verse slots merged"] += len(verses) - 1
                    results[code].append(make_entry(
                        code, chapter, min(verses), max(verses), "John Calvin", "Commentary",
                        "1509–1564", "Reformed", "calvin", body, basis="block", tier="tier1"))
                    continue
                start, end, basis = slot, slot, "anchored"
                marker = CALVIN_MARKER.match(text)
                if marker:
                    m_start = int(marker.group(2))
                    m_end = int(marker.group(3)) if marker.group(3) else m_start
                    if m_start == slot and m_end >= m_start:
                        start, end, basis = m_start, m_end, "stated"
                    else:
                        note("calvin marker disagrees with slot (kept at slot, anchored)",
                             f"{code} {chapter}:{slot} text begins {marker.group(0)!r}")
                results[code].append(make_entry(
                    code, chapter, start, end, "John Calvin", "Commentary", "1509–1564",
                    "Reformed", "calvin", text, basis=basis, tier="tier1"))
    return results


# ---------------------------------------------------------------- Fathers

FATHER_MAX_SPAN = 30

# Sourced attribution corrections: the Historical Christian Faith database files some catena
# material under the wrong person. Cards and profiles show the corrected name; admission, ranking
# and the per-verse cap still key off the database name. Add an entry only with a public-domain
# source recorded in that author's profile.
#   Remigius: the Gospel comments filed under "Remigius of Rheims" (d. c. 533) come from Aquinas's
#   Catena Aurea, which cites the Carolingian scholar Remigius of Auxerre (d. 908). Wace & Piercy
#   (1911) record no exegetical work by Remigius of Rheims; Catholic Encyclopedia s.v. "Remigius of
#   Auxerre". Kept (clearly dated, post-patristic) because the material circulates widely in the
#   catena tradition. Found by workstream L, corrected by Claude, 2026-09-23.
ATTRIBUTION_CORRECTIONS = {
    "Remigius of Rheims": ("Remigius of Auxerre", "d. 908"),
}
_DATABASE_NAME_FOR = {display: db for db, (display, _) in ATTRIBUTION_CORRECTIONS.items()}

# Sourced work-specific URL overrides: the Historical Christian Faith database itself has no
# source_url for these (father_name, source_title) pairs (verified directly against
# commentaries.sqlite, 2026-09-24, workstream M, 0.9.5), so without an override every card for
# these rows falls back to Models.swift's generic whole-repository link. Add an entry here only
# with a specific, hand-verified, honestly public-domain page for that exact named work -- never a
# guess, and never a paywalled/copyrighted modern translation's page.
#
# Scale note: a full scan found 9,372 shipped Fathers entries (6,714 distinct author/work
# combinations) with no per-row URL in the source database -- not "23" (that figure, from the
# 0.9.3 pastor-QA pass, was a spot-check sample size, not the true population; see the 0.9.5
# build report and CONTENT-ROADMAP.md for the corrected count). A hand-curated map cannot
# responsibly close a gap that size without either guessing URLs or linking modern copyrighted
# editions; this map holds only the entries actually verified. The much larger remainder is
# handled honestly by the UI-facing distinction proposed in the 0.9.5 report (Claude/workstream N
# to implement in Models.swift/Panes.swift, which this workstream does not own).
#
#   Theodoret of Cyrus, "Interpretation of the Letter to the Romans": an 1839-40 English
#   translation (Christian Remembrancer vols 21-22, translator unrecorded, no modern copyright
#   holder identified) hosted at tertullian.org, confirmed by direct fetch to be the actual text
#   of this specific commentary (not a placeholder/index page). Part 2 exists at the same site;
#   Part 1 is used as the work's landing page, consistent with how every other source in this
#   app's registry links to the work as a whole rather than a specific chapter.
FATHERS_SOURCE_URL_OVERRIDES: dict[tuple[str, str], str] = {
    ("Theodoret of Cyrus", "INTERPRETATION OF THE LETTER TO THE ROMANS"):
        "https://www.tertullian.org/fathers/theodoret_commentary_on_romans_01.htm",
}

# A full-corpus scan (all rows the build could possibly emit, run 2026-09-22 while adding
# Gill/Henry) found pre-existing Fathers rows leaking literal backslash escapes as visible
# text -- none of it introduced by this pass (mhcc/calvin/hcf were already shipping this data).
# Three shapes were found by direct inspection: a literal \" around a nested quotation (e.g.
# Ambrose on Psalm 37), a literal \n mid-sentence (Jerome on Zechariah 14:8), and a bare
# backslash immediately before a quote or space, apparently a garbled curly-quote (Jerome on
# Ezekiel 41:3, "...Holies.\\ \" Let us..."). A literal backslash never legitimately belongs in
# this dataset's cleaned prose (verified: every occurrence found across all ~52,000 rows was one
# of these three artifacts), so after unescaping the two meaningful cases, anything left is
# simply stripped rather than maintaining a growing list of special cases.
def unescape_fathers_text(text: str) -> str:
    if "\\" not in text:
        return text
    REPORT_DATA["cleaned"]["fathers: removed a stray literal backslash artifact"] += 1
    text = text.replace('\\"', '"').replace("\\n", " ")
    return text.replace("\\", "")


# Tier 3: shown only when the reader explicitly opts in (see ConfessionalTier.tier3ResearchOnly
# in Models.swift). Same already-licensed database as the default bank; the difference is settled
# reception, not licensing or category. Since 0.8 (workstream I) this bucket is the *computed*
# `_ADMISSION["condemned"]` list (council-condemned authors within the patristic categories/era,
# per the admission rule documented above), not a hand-picked name list -- see that block for the
# two places a real source overrode the database's own flag.
def _select_fathers(names: list[str], rank: dict[str, int], tier: str, max_per_verse: int) -> dict[str, list[dict]]:
    """Shared selection logic for both the Tier 2 (default) and Tier 3 (research-only) father
    passes: same database, same range validation. Only the name list, tier label and per-verse cap
    differ -- `names` already encodes the condemned/pseudonymous/era filtering (via
    `_father_admission`), so this no longer re-applies `condemned_by_council = 0` itself, which
    would incorrectly zero out the Tier-3 pass (its whole membership is condemned=1 rows)."""
    database = WORK / "commentaries.sqlite"
    results = defaultdict(list)
    if not database.exists() or not names:
        return results
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    placeholders = ",".join("?" for _ in names)
    rows = connection.execute(f"""
        SELECT c.id AS row_id, c.father_name, c.file_name, c.book, c.location_start, c.location_end,
               c.txt, c.source_url, c.source_title,
               m.default_year, m.father_category, m.condemned_by_council
        FROM commentary c JOIN father_meta m ON m.name = c.father_name
        WHERE c.father_name IN ({placeholders})
        ORDER BY c.id
    """, names).fetchall()
    connection.close()

    by_verse = defaultdict(list)
    code_by_db = {slug: code for code, _, _, slug in BOOKS}
    for row in rows:
        code = code_by_db.get(row["book"])
        if not code:
            REPORT_DATA["dropped"]["fathers: book not in canon"] += 1
            continue
        start_chapter, start_verse = divmod(int(row["location_start"]), 1_000_000)
        end_chapter, end_verse = divmod(int(row["location_end"]), 1_000_000)
        if start_chapter != end_chapter:
            REPORT_DATA["dropped"]["fathers: range crosses a chapter boundary"] += 1
            continue
        if start_verse < 1 or end_verse < start_verse:
            REPORT_DATA["dropped"]["fathers: invalid verse range (end before start)"] += 1
            continue
        if end_verse - start_verse + 1 > FATHER_MAX_SPAN:
            REPORT_DATA["dropped"][f"fathers: range wider than {FATHER_MAX_SPAN} verses"] += 1
            continue
        excerpt = clean(unescape_fathers_text(row["txt"]))
        truncated = len(excerpt) > 1800
        if truncated:
            excerpt = excerpt[:1799].rsplit(" ", 1)[0] + "…"
        # A handful of rows have no source_title, and their file_name is the raw import
        # filename ("Song of Solomon 1_1.toml"), not a real title -- showing that verbatim
        # read as unprofessional filename leakage. Fall back to the same generic label already
        # used when both fields are empty rather than surface the filename.
        raw_title = row["source_title"] or row["file_name"] or ""
        work = "Historical commentary" if raw_title.endswith(".toml") else (raw_title or "Historical commentary")
        author = row["father_name"]
        era = f"d. {row['default_year']}" if row["default_year"] and row["default_year"] != "9999" else "Early church"
        if author in ATTRIBUTION_CORRECTIONS:
            author, era = ATTRIBUTION_CORRECTIONS[author]
        url_override = FATHERS_SOURCE_URL_OVERRIDES.get((row["father_name"], row["source_title"] or ""))
        if url_override:
            REPORT_DATA["cleaned"]["fathers: applied a hand-curated work-specific source URL"] += 1
        item = make_entry(
            code, start_chapter, start_verse, end_verse, author, work, era,
            "Fathers", "hcf", excerpt, row["source_url"] or url_override or None, truncated=truncated,
            tier=tier, content_kind=classify_father_content_kind(work))
        for verse in range(start_verse, end_verse + 1):
            by_verse[(code, start_chapter, verse)].append(item)

    seen: set[str] = set()
    for (code, _, _), candidates in sorted(by_verse.items()):
        candidates.sort(key=lambda x: (rank.get(_DATABASE_NAME_FOR.get(x["author"], x["author"]), 999), x["work"], x["id"]))
        chosen, authors = [], set()
        for item in candidates:
            if item["author"] in authors:
                continue
            chosen.append(item)
            authors.add(item["author"])
            if len(chosen) == max_per_verse:
                break
        for item in chosen:
            if item["id"] in seen:
                continue
            seen.add(item["id"])
            results[code].append(item)
    return results


def parse_fathers() -> dict[str, list[dict]]:
    # max_per_verse raised 2 -> 4 for 0.8: the default bank grew roughly tenfold (21 curated
    # names -> a full patristic-era admission), so two slots per verse would now silently hide
    # far more of the added breadth than it shows. Four keeps a verse's Fathers stack scannable
    # (matches the existing per-card collapse/author-grouping UI) while actually surfacing the
    # broadened bank Matt asked for; a verse with more than four applicable Fathers still shows
    # the four highest-ranked (see FATHER_PRIORITY/`_father_admission`'s row-count ranking).
    return _select_fathers(_ADMISSION["default"], FATHER_RANK, tier="tier2", max_per_verse=4)


def parse_fathers_research() -> dict[str, list[dict]]:
    # max_per_verse raised 1 -> 2 for 0.8: the condemned bucket grew 5 -> 9 names.
    return _select_fathers(_ADMISSION["condemned"], TIER3_RANK, tier="tier3", max_per_verse=2)


# ---------------------------------------------------------------- Assembly

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(directory: Path) -> str:
    digest = hashlib.sha256()
    if not directory.exists():
        return "MISSING:" + directory.name
    for path in sorted(directory.rglob("*.json")):
        digest.update(str(path.relative_to(directory)).encode())
        digest.update(sha256_file(path).encode())
    return digest.hexdigest()


def input_hashes() -> dict[str, str]:
    hashes = {
        "crossreferences_bsb.tsv": sha256_file(WORK / "crossreferences_bsb.tsv"),
        "commentaries.sqlite": sha256_file(WORK / "commentaries.sqlite"),
        "pillar/c/calvin (tree)": tree_hash(CALVIN),
        "helloao/john-gill (tree)": tree_hash(HELLOAO / "john-gill"),
        "helloao/matthew-henry (tree)": tree_hash(HELLOAO / "matthew-henry"),
        # Integrated 2026-09-23 (workstream E, 0.7 wave 2, E2) into the new Exegetes bank.
        "helloao/keil-delitzsch (tree)": tree_hash(HELLOAO / "keil-delitzsch"),
        "helloao/jamieson-fausset-brown (tree)": tree_hash(HELLOAO / "jamieson-fausset-brown"),
        # New 2026-09-24 (workstream M, 0.9.5): Isaiah 49-66 Calvin gap-fill -- see SOURCES["calvin-helloao"].
        "helloao/calvin-helloao (tree)": tree_hash(HELLOAO / "calvin-helloao"),
        # Restored 2026-09-23 (workstream E, 0.7 wave 2, E3), gap-only -- see parse_mhcc().
        "mhcc.txt": sha256_file(MHCC_PATH) if MHCC_PATH.exists() else "MISSING",
        # 0.8 (workstream I): hand-curated theological-profile source, hashed for reproducibility
        # tracking like every other raw input, even though it is text Claude wrote (from sourced
        # facts) rather than a downloaded dataset.
        "fathers-profiles.source.json": sha256_file(FATHERS_PROFILES_SOURCE) if FATHERS_PROFILES_SOURCE.exists() else "MISSING",
    }
    return hashes


def dump(payload) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


# ---------------------------------------------------------------- Father theological profiles
# (0.8, workstream I)
#
# Curated by hand in work-content/fathers-profiles.source.json -- one record per author, each
# field sourced from a specific public-domain reference (Wace & Piercy's 1911 Dictionary of
# Christian Biography, mirrored article-for-article on Wikisource, for every author within its
# stated "to the end of the sixth century" scope; Schaff's NPNF for the one author outside that
# scope, John Damascene). This function only validates and repackages that hand-written source
# into the schema Swift decodes -- it never invents or infers a field. A profile with no `sources`
# entries, or a `name` that never appears as `father_name` in a currently-admitted or
# currently-condemned entry, fails the build loudly rather than shipping silently wrong.
PROFILE_REQUIRED_TEXT_FIELDS = ("dates", "region", "see", "language", "school",
                                 "ecclesialRecognition", "controversies", "receptionByReformers")


def build_father_profiles(out: Path) -> dict:
    if not FATHERS_PROFILES_SOURCE.exists():
        raise SystemExit(f"missing {FATHERS_PROFILES_SOURCE} -- Fathers theological profiles are required, not optional")
    raw = json.loads(FATHERS_PROFILES_SOURCE.read_text(encoding="utf-8"))
    admitted = set(_ADMISSION["default"]) | set(_ADMISSION["condemned"])
    seen_names: set[str] = set()
    coverage = Counter()
    field_counts = Counter()
    profiles = []
    for entry in raw["profiles"]:
        name = entry["name"]
        if name in seen_names:
            raise SystemExit(f"duplicate father profile: {name}")
        seen_names.add(name)
        if _DATABASE_NAME_FOR.get(name, name) not in admitted:
            raise SystemExit(f"father profile {name!r} does not match any admitted or condemned author name "
                              f"(check it against father_meta.name exactly)")
        sources = entry.get("sources") or []
        if not sources or any(not s.get("title") or not s.get("url") for s in sources):
            raise SystemExit(f"father profile {name!r} has no valid source citation -- every profile must cite one")
        emphases = entry.get("emphases") or []
        if len(emphases) > 3:
            raise SystemExit(f"father profile {name!r} has {len(emphases)} emphases -- spec caps this at 1-3")
        conciliar = entry.get("conciliarJudgment")
        profile = {
            "name": name,
            "dates": entry.get("dates"),
            "region": entry.get("region"),
            "see": entry.get("see"),
            "language": entry.get("language"),
            "school": entry.get("school"),
            "ecclesialRecognition": entry.get("ecclesialRecognition"),
            "emphases": emphases,
            "controversies": entry.get("controversies"),
            "receptionByReformers": entry.get("receptionByReformers"),
            "conciliarJudgment": conciliar,
            "sources": sources,
        }
        profiles.append(profile)
        coverage["total"] += 1
        if _DATABASE_NAME_FOR.get(name, name) in set(_ADMISSION["default"]):
            coverage["defaultBankProfiled"] += 1
        else:
            coverage["condemnedBucketProfiled"] += 1
        if profile["school"] and profile["region"]:
            coverage["schoolAndRegion"] += 1
        for field in PROFILE_REQUIRED_TEXT_FIELDS:
            if profile.get(field):
                field_counts[field] += 1
        if emphases:
            field_counts["emphases"] += 1
        if conciliar:
            field_counts["conciliarJudgment"] += 1

    profiles.sort(key=lambda p: p["name"])
    (out / "fathers-profiles.json").write_text(
        dump({"schema": 1, "profiles": profiles}), encoding="utf-8")

    unprofiled_default = sorted(set(_ADMISSION["default"]) - seen_names)
    unprofiled_condemned = sorted(set(_ADMISSION["condemned"]) - seen_names)
    return {
        "profileCount": len(profiles),
        "defaultBankAdmitted": len(_ADMISSION["default"]),
        "defaultBankProfiled": coverage["defaultBankProfiled"],
        "condemnedBucketAdmitted": len(_ADMISSION["condemned"]),
        "condemnedBucketProfiled": coverage["condemnedBucketProfiled"],
        "authorsWithSchoolAndRegion": coverage["schoolAndRegion"],
        "fieldCoverage": dict(field_counts),
        "unprofiledDefaultBankAuthors": unprofiled_default,
        "unprofiledCondemnedAuthors": unprofiled_condemned,
    }


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=OUT,
                         help="Output root for Resources/Study (default: the real bundled path). "
                              "Point this at a /private/tmp staging directory to build without touching "
                              "the live resources, then swap the verified result into place.")
    args = parser.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    crossrefs = parse_crossrefs()
    calvin = parse_calvin()
    # 0.10 (workstream R2): Calvin on the Psalms -- HelloAO's per-verse text replaces Pillar's one
    # repeated block per psalm wherever Pillar has only that block; see build_calvin_psalms().
    calvin_psalms = build_calvin_psalms(calvin["PSA"])
    calvin["PSA"] = calvin_psalms["pillar"] + calvin_psalms["intros"]
    fathers = parse_fathers()
    fathers_research = parse_fathers_research()
    # E1 (0.7 wave 2): Gill moves to the new Tier-2 "Exegetes" bank, labelled Particular Baptist --
    # "REFORMED" now means Tier 1 only. E2: Keil & Delitzsch (OT, Lutheran) and
    # Jamieson-Fausset-Brown (Presbyterian & Anglican) join the same bank, same parser, same
    # data-quality rigor (markup-leakage/mojibake/emphasis-leak cleaning all apply identically).
    gill = parse_helloao_commentary("john-gill", "John Gill", "Exposition of the Old and New Testament", "1697–1771",
                                     tradition="Exegetes", tier="tier2", author_tradition="Particular Baptist")
    henry = parse_helloao_commentary("matthew-henry", "Matthew Henry", "Commentary on the Whole Bible", "1662–1714")
    keil_delitzsch = parse_helloao_commentary(
        "keil-delitzsch", "Keil & Delitzsch", "Old Testament Commentary", "19th century",
        tradition="Exegetes", tier="tier2", author_tradition="Lutheran")
    jfb = parse_helloao_commentary(
        "jamieson-fausset-brown", "Jamieson, Fausset & Brown",
        "Commentary Critical and Explanatory on the Whole Bible", "19th century",
        tradition="Exegetes", tier="tier2", author_tradition="Presbyterian & Anglican")
    # E3: backfill Matthew Henry's *Concise* Commentary, labelled "Concise Commentary", but only
    # for the exact chapters the Complete leaves at zero -- recomputed from `henry`'s own output,
    # never a hardcoded list (see mhcc_gap_chapters's doc comment).
    mhcc_gaps = mhcc_gap_chapters(henry)
    mhcc = parse_mhcc(mhcc_gaps)
    # New 2026-09-24 (workstream M, 0.9.5): Isaiah 49-66 Calvin gap-fill from HelloAO's
    # independent digitization of the same commentary -- see SOURCES["calvin-helloao"] and
    # work-content/helloao/calvin-helloao/_fetch-manifest.json. Reuses the same generic HelloAO
    # parser as Gill/Henry/Keil-Delitzsch/JFB (mojibake repair, markup-leak drop, etc. all apply);
    # only ISA 49-66 exist under work-content/helloao/calvin-helloao/, so nothing else is emitted.
    calvin_isa_gap_fill = parse_helloao_commentary(
        "calvin-helloao", "John Calvin", "Commentary", "1509–1564", tradition="Reformed", tier="tier1",
        books={"ISA"}, text_filter=strip_calvin_helloao_apparatus)
    # The Psalms half of the same source is parsed by build_calvin_psalms() above; merged here.
    calvin_gap_fill_psa = calvin_psalms["helloao"]

    totals: Counter = Counter()
    per_source: Counter = Counter()
    basis_counts: Counter = Counter()
    tier_counts: Counter = Counter()
    kind_counts: Counter = Counter()
    chapters_written = 0
    id_collisions = 0
    reformed_covered = 0
    total_canon_chapters = 0
    mhcc_backfilled_chapters = 0
    for code, name, _, _ in BOOKS:
        merged: dict[str, dict] = {}
        book_items = (calvin[code] + fathers[code] + fathers_research[code] + crossrefs[code]
                      + gill[code] + henry[code] + keil_delitzsch[code] + jfb[code] + mhcc[code]
                      + calvin_isa_gap_fill[code] + (calvin_gap_fill_psa if code == "PSA" else []))
        for item in book_items:
            if item["id"] in merged:
                id_collisions += 1
                REPORT_DATA["dropped"]["duplicate id (identical content and range)"] += 1
                continue
            merged[item["id"]] = item

        by_chapter: dict[int, list[dict]] = defaultdict(list)
        for item in merged.values():
            by_chapter[item["chapter"]].append(item)

        counts = BSB_VERSE_COUNTS.get(code)
        if counts:
            total_canon_chapters += len(counts)
            for chapter in range(1, len(counts) + 1):
                if any(item["tradition"] == "Reformed" for item in by_chapter.get(chapter, [])):
                    reformed_covered += 1
        mhcc_backfilled_chapters += len({item["chapter"] for item in mhcc[code]})

        book_dir = out / code
        if book_dir.exists():
            for stale in book_dir.glob("*.json"):
                stale.unlink()
        book_dir.mkdir(parents=True, exist_ok=True)
        for chapter, items in by_chapter.items():
            # A psalm introduction (0.10, R2) sorts ahead of the verse-1 commentary it introduces; the
            # extra key is constant (1) for every other entry, so no other order changes.
            items.sort(key=lambda x: (x["startVerse"], x["endVerse"],
                                       TRADITION_ORDER[x["tradition"]], x["author"],
                                       0 if x["work"].startswith(PSALM_INTRO_WORK) else 1, x["work"], x["id"]))
            (book_dir / f"{chapter}.json").write_text(
                dump({"schema": SCHEMA, "code": code, "book": name, "chapter": chapter, "entries": items}),
                encoding="utf-8")
            chapters_written += 1
        for item in merged.values():
            totals[item["tradition"]] += 1
            per_source[item["source"]] += 1
            basis_counts[item["rangeBasis"]] += 1
            tier_counts[item["tier"]] += 1
            kind_counts[item["contentKind"]] += 1

    (out / "sources.json").write_text(dump({"schema": SCHEMA, "sources": SOURCES}), encoding="utf-8")
    profile_report = build_father_profiles(out)

    # 0.8 (workstream I): exact inclusion/exclusion counts for the broadened Fathers admission
    # rule, recomputed every build from the same query `_father_admission()` used to build the
    # bank itself -- never hand-maintained, so a future database update is reflected automatically.
    database_path = WORK / "commentaries.sqlite"
    category_totals: dict[str, int] = {}
    excluded_category_totals: dict[str, int] = {}
    if database_path.exists():
        conn = sqlite3.connect(database_path)
        for cat, in conn.execute("SELECT DISTINCT father_category FROM father_meta"):
            n = conn.execute("SELECT COUNT(*) FROM father_meta WHERE father_category = ?", (cat,)).fetchone()[0]
            if cat in PATRISTIC_CATEGORIES:
                category_totals[cat] = n
            elif cat in EXCLUDED_FATHER_CATEGORIES:
                excluded_category_totals[cat] = n
        conn.close()
    fathers_admission_report = {
        "rule": f"category in {PATRISTIC_CATEGORIES} AND default_year <= {PATRISTIC_YEAR_CUTOFF} "
                f"AND NOT condemned (verified), excluding {EXCLUDED_FATHER_CATEGORIES}",
        "patristicCategoryTotals": category_totals,
        "excludedNonPatristicCategoryTotals": excluded_category_totals,
        "admittedDefaultBank": len(_ADMISSION["default"]),
        "admittedDefaultBankWithContent": sum(1 for n in _ADMISSION["default"] if _ADMISSION["rowCount"].get(n, 0) > 0),
        "condemnedBucket": _ADMISSION["condemned"],
        "excludedLateOrMedieval": len(_ADMISSION["excludedLate"]),
        "profiles": profile_report,
    }

    report = {
        "schema": SCHEMA,
        "books": len(BOOKS),
        "chapterFilesWritten": chapters_written,
        "entriesByTradition": dict(totals),
        "entriesBySource": dict(per_source),
        "entriesByRangeBasis": dict(basis_counts),
        "entriesByTier": dict(tier_counts),
        "entriesByContentKind": dict(kind_counts),
        "idCollisions": id_collisions,
        "cleaned": dict(REPORT_DATA["cleaned"]),
        "dropped": dict(REPORT_DATA["dropped"]),
        "needsHumanReview": {kind: items for kind, items in REPORT_DATA["notes"].items()},
        "inputSHA256": input_hashes(),
        # E1-E3 (0.7 wave 2): Reformed (Tier 1) chapter coverage after Gill's move out of the
        # bank and the mhcc gap-fill's move back in, and exactly which chapters the gap-fill
        # covered -- both recomputed every build, never hand-maintained.
        "reformedChapterCoverage": {
            "coveredChapters": reformed_covered,
            "totalChapters": total_canon_chapters,
            "percent": round(100 * reformed_covered / total_canon_chapters, 2) if total_canon_chapters else 0,
        },
        "mhccGapFill": {
            "chaptersRequested": sum(len(v) for v in mhcc_gap_chapters(henry).values()),
            "chaptersFilled": mhcc_backfilled_chapters,
            "byBook": {code: sorted(chapters) for code, chapters in sorted(mhcc_gap_chapters(henry).items())},
        },
        # New 2026-09-24 (workstream M, 0.9.5): see SOURCES["calvin-helloao"].
        "calvinIsaiahGapFill": {
            "chaptersRequested": 18,
            "chaptersFilled": len({item["chapter"] for item in calvin_isa_gap_fill["ISA"]}) if calvin_isa_gap_fill["ISA"] else 0,
            "chapters": sorted({item["chapter"] for item in calvin_isa_gap_fill["ISA"]}),
            "note": "Pillar's cached Calvin conversion has empty content for Isaiah 49-66; HelloAO's "
                    "independent digitization of the same commentary fills all 18 chapters. See "
                    "CONTENT-SOURCES.md and work-content/helloao/calvin-helloao/_fetch-manifest.json.",
        },
        # New 2026-09-24 (workstream R2, 0.10): see build_calvin_psalms() for the precedence rule.
        "calvinPsalms": {
            **{k: v for k, v in calvin_psalms["report"].items() if k not in ("perChapterEntries", "sameTranslationCoverage")},
            "chaptersImprovedCount": len(calvin_psalms["report"]["chaptersImproved"]),
            "sameTranslationCoverageMin": min(calvin_psalms["report"]["sameTranslationCoverage"].values(), default=None),
            "sameTranslationCoverageMedian": (sorted(calvin_psalms["report"]["sameTranslationCoverage"].values())[
                len(calvin_psalms["report"]["sameTranslationCoverage"]) // 2]
                if calvin_psalms["report"]["sameTranslationCoverage"] else None),
            "sameTranslationCoverageByChapter": {str(k): v for k, v in sorted(calvin_psalms["report"]["sameTranslationCoverage"].items())},
            "entriesPerChapter": calvin_psalms["report"]["perChapterEntries"],
            "rule": "Pillar block-only chapters -> HelloAO per-verse entries + Pillar's psalm introduction at verse 1; "
                    "chapters where Pillar has per-verse text keep Pillar; fallback to the Pillar block if the "
                    "same-translation check (>= 0.90 shared 6-word shingles) or the HelloAO parse fails.",
        },
        # New 2026-09-24 (workstream M, 0.9.5): see FATHERS_SOURCE_URL_OVERRIDES.
        "fathersSourceURLGap": {
            "handCuratedOverridesApplied": REPORT_DATA["cleaned"].get(
                "fathers: applied a hand-curated work-specific source URL", 0),
            "note": "9,372 shipped Fathers entries (6,714 distinct author/work combinations) have no "
                    "per-row source_url in the Historical Christian Faith database itself -- not '23' "
                    "(that figure was a QA spot-check sample size, not the true population; see "
                    "CONTENT-ROADMAP.md). FATHERS_SOURCE_URL_OVERRIDES holds only the entries this "
                    "workstream could actually verify a specific, honestly public-domain source page "
                    "for; the rest still fall back to Models.swift's generic repository link, and a UI "
                    "honesty fix (distinguishing a work-specific link from a database-only fallback) is "
                    "proposed in the 0.9.5 report rather than implemented here.",
        },
        "fathersAdmission": fathers_admission_report,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("Generated", len(BOOKS), "book indexes,", chapters_written, "chapter files (schema", SCHEMA, ")", dict(totals))
    print("Reformed chapter coverage:", report["reformedChapterCoverage"])
    print("mhcc gap-fill:", report["mhccGapFill"]["chaptersFilled"], "/", report["mhccGapFill"]["chaptersRequested"], "requested chapters filled")
    print("calvin Isaiah gap-fill:", report["calvinIsaiahGapFill"]["chaptersFilled"], "/", report["calvinIsaiahGapFill"]["chaptersRequested"], "chapters filled")
    psalm_report = report["calvinPsalms"]
    print("calvin Psalms:", psalm_report["chaptersImprovedCount"], "chapters now per-verse (HelloAO),",
          psalm_report["helloaoEntries"], "entries +", psalm_report["introEntries"], "introductions;",
          "kept Pillar per-verse:", psalm_report["chaptersKeptPillarPerVerse"],
          "fallback:", psalm_report["chaptersFallbackToPillarBlock"],
          "min same-translation coverage:", psalm_report["sameTranslationCoverageMin"])
    print("fathers source-URL overrides applied:", report["fathersSourceURLGap"]["handCuratedOverridesApplied"])
    print("Fathers admission:", fathers_admission_report["admittedDefaultBank"], "default /",
          len(fathers_admission_report["condemnedBucket"]), "condemned / profiles",
          profile_report["profileCount"])
    print("cleaned:", dict(REPORT_DATA["cleaned"]))
    print("dropped:", dict(REPORT_DATA["dropped"]))


if __name__ == "__main__":
    sys.exit(main())
