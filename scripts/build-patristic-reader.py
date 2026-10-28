#!/usr/bin/env python3
"""Build an offline, chapter-indexed Project Gutenberg Apostolic Fathers reader.

Reads the pinned text export from work-content and writes only the
dedicated Reference resource plus its rights evidence. Uses only Python stdlib.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INPUT = ROOT / "resource-inputs/apostolic-fathers-77576.txt"
REFERENCE = ROOT / "Sources/StudyTable/Resources/Reference"
LICENSES = ROOT / "Sources/StudyTable/Resources/Licenses"
SOURCE_URL = "https://www.gutenberg.org/files/77576/77576-h/77576-h.htm"
EXPECTED_SOURCE_SHA256 = "2a50a9cb4e98ab58a01fc6e11df700a9ab685b638d52be954fc0a7467eb598cb"
BOOK_ID = "apostolic-fathers-1870"
MAX_ARTICLE_CHARS = 11_000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def norm_lines(text: str) -> list[str]:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    # Gutenberg's plain-text conversion wraps paragraphs. Keep the original
    # words and footnote markers while removing only page-number-only lines.
    return [line.rstrip() for line in lines if not re.fullmatch(r"\s*\d{1,4}\s*", line)]


def is_heading(block: str) -> bool:
    s = " ".join(block.split())
    if not s:
        return False
    if re.match(r"^(?:CHAP\.?|CHAPTER)\s+[IVXLCDM0-9]+\b", s, re.I):
        return True
    if s.casefold() in {"shorter.", "longer.", "introductory notice.", "appendix."}:
        return True
    if re.match(r"^(?:VISION|COMMANDMENT|SIMILITUDE)\s+(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH|SEVENTH|EIGHTH|NINTH|TENTH|ELEVENTH|TWELFTH)\.?$", s, re.I):
        return True
    # Distinguish actual display headings from prose and all-cap running
    # titles: source titles are short blocks in capitals and end in a period.
    letters = [c for c in s if c.isalpha()]
    return bool(letters and len(s) <= 145 and s.endswith(".") and
                sum(c.isupper() for c in letters) / len(letters) > .88)


def paragraph_blocks(text: str) -> list[str]:
    lines = norm_lines(text)
    blocks: list[str] = []
    current: list[str] = []
    for line in lines:
        if not line.strip():
            if current:
                blocks.append(" ".join(x.strip() for x in current if x.strip()))
                current = []
        else:
            current.append(line)
    if current:
        blocks.append(" ".join(x.strip() for x in current if x.strip()))
    return blocks


def make_articles(text: str) -> list[dict]:
    blocks = paragraph_blocks(text)
    # The printed contents also mentions the appendix; use the final source
    # occurrence so only the actual appendix changes the authenticity label.
    spurious_start = max(i for i, block in enumerate(blocks)
                         if "SPURIOUS EPISTLES OF IGNATIUS" in block.upper())
    result: list[dict] = []
    active_title = "Opening editorial matter"
    current_work = active_title
    current_section = active_title
    current_subsection = ""
    spurious_appendix = False
    active: list[str] = []

    def emit() -> None:
        nonlocal active
        body = "\n\n".join(active).strip()
        if not body:
            active = []
            return
        # Keep every paragraph; chunk only when needed, at paragraph borders.
        chunks: list[list[str]] = []
        chunk: list[str] = []
        size = 0
        for para in active:
            if chunk and size + len(para) > MAX_ARTICLE_CHARS:
                chunks.append(chunk)
                chunk, size = [], 0
            chunk.append(para)
            size += len(para) + 2
        if chunk:
            chunks.append(chunk)
        for part, paragraphs in enumerate(chunks, 1):
            suffix = f" · part {part}" if len(chunks) > 1 else ""
            n = len(result) + 1
            result.append({"id": f"af-{n:04d}", "title": active_title + suffix,
                           "body": "\n\n".join(paragraphs), "anchor": None})
        active = []

    for block_index, block in enumerate(blocks):
        if block_index >= spurious_start:
            spurious_appendix = True
        if is_heading(block):
            heading = " ".join(block.split()).replace("—", " — ")
            if heading.casefold() in {"shorter.", "longer."}:
                # These labels distinguish recensions inside each Ignatian
                # chapter. Keep the chapter heading attached to its text.
                if active and not (len(active) == 1 and
                                   re.match(r"^(?:CHAP\.?|CHAPTER)\s", active[0], re.I)):
                    emit()
                active_title = f"{current_section} · {heading[:-1]} recension"
                active.append(block)
            else:
                emit()
                upper = heading.upper()
                if re.match(r"^(?:CHAP\.?|CHAPTER)\s", heading, re.I):
                    parts = [current_work]
                    if current_subsection:
                        parts.append(current_subsection)
                    active_title = " — ".join(parts + [heading])
                    if spurious_appendix and not active_title.startswith("[Spurious appendix]"):
                        active_title = "[Spurious appendix] " + active_title
                    current_section = active_title
                elif heading.casefold().startswith("introductory notice"):
                    active_title = f"{current_work} — Introductory notice"
                    current_section = active_title
                elif re.match(r"^(?:VISION|COMMANDMENT|SIMILITUDE)\s", heading, re.I):
                    current_subsection = heading
                    current_section = f"{current_work} — {heading}"
                    active_title = current_section
                elif upper.startswith("CONTENTS OF VOL"):
                    active_title = "Original printed contents (page references are to the 1870 edition)"
                    current_section = active_title
                else:
                    active_title = heading
                    if (heading.startswith(("THE ", "FRAGMENTS OF ", "INDEX OF ")) or
                            upper == "APPENDIX." or
                            (spurious_appendix and "SPURIOUS EPISTLES OF IGNATIUS" in upper)):
                        current_work = heading
                        current_subsection = ""
                        if spurious_appendix and not upper.startswith("INDEX OF "):
                            current_work = "[Spurious appendix] " + current_work
                        current_section = current_work
                        if not upper.startswith("INDEX OF "):
                            active_title = current_work
                # Keep heading text in the article body too, so the chapter's
                # printed title and chapter number travel with its text.
                active = [block]
        else:
            active.append(block)
    emit()
    return result


def main() -> None:
    raw = INPUT.read_bytes()
    source_hash = sha256(raw)
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f"Unexpected source checksum: {source_hash}")
    text = raw.decode("utf-8-sig")
    start_marker = "*** START OF THE PROJECT GUTENBERG EBOOK"
    end_marker = "*** END OF THE PROJECT GUTENBERG EBOOK"
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        raise SystemExit("Expected one Project Gutenberg start and end marker")
    body = text.split(start_marker, 1)[1].split("\n", 1)[1].split(end_marker, 1)[0]
    license_marker = "START: FULL LICENSE"
    license_text = text[text.index(license_marker):].strip() + "\n"
    articles = make_articles(body)
    expected = paragraph_blocks(body)
    actual = [p for article in articles for p in paragraph_blocks(article["body"])]
    if Counter(expected) != Counter(actual):
        raise SystemExit("Paragraph coverage check failed: source paragraphs were lost or changed")
    credit = (
        "Source and use notice\n\n"
        "This reader reproduces The Writings of the Apostolic Fathers, Ante-Nicene Christian "
        "Library, vol. I (Edinburgh: T. & T. Clark, 1870), edited by Alexander Roberts and "
        "James Donaldson; translated by Alexander Roberts, James Donaldson, and Frederick "
        "Crombie. Project Gutenberg eBook 77576: " + SOURCE_URL + ". The source edition labels "
        "the shorter and longer Ignatian recensions separately and identifies the appendix as "
        "spurious; those labels are retained here and are not a claim that every work is "
        "authentic to its traditional author. This 1870 text is public domain in the United "
        "States; copyright status may differ elsewhere, so follow local law. The complete "
        "Project Gutenberg license is reproduced as this reader's final article."
    )
    articles.insert(0, {"id": "af-0001", "title": "Source credits and use notice",
                       "body": credit, "anchor": None})
    articles.append({"id": "af-license", "title": "Project Gutenberg full license",
                     "body": license_text, "anchor": None})
    for i, article in enumerate(articles[:-1], 1):
        article["id"] = f"af-{i:04d}"
    ids = [a["id"] for a in articles]
    if not articles or len(set(ids)) != len(ids):
        raise SystemExit("Generated article list is empty or has duplicate IDs")
    book = {
        "id": BOOK_ID,
        "title": "The Writings of the Apostolic Fathers (1870 translation)",
        "author": "Clement of Rome, Hermas, Ignatius of Antioch, Papias, Polycarp, and others",
        "attribution": (
            "The Writings of the Apostolic Fathers, Ante-Nicene Christian Library, vol. I "
            "(Edinburgh: T. & T. Clark, 1870), edited by Alexander Roberts and James Donaldson; "
            "translated by Alexander Roberts, James Donaldson, and Frederick Crombie. Source: "
            f"Project Gutenberg eBook 77576 ({SOURCE_URL}). Project Gutenberg full license is "
            "included in the source edition and reproduced at Resources/Licenses/" 
            "project-gutenberg-77576-full-license.txt. This 1870 text is public domain in the "
            "United States; copyright status may differ elsewhere, so readers must follow local law."
        ),
        "source": SOURCE_URL,
        "articles": articles,
    }
    REFERENCE.mkdir(parents=True, exist_ok=True)
    LICENSES.mkdir(parents=True, exist_ok=True)
    out_path = REFERENCE / "apostolic-fathers.json"
    out_bytes = (json.dumps(book, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()
    out_path.write_bytes(out_bytes)
    (LICENSES / "project-gutenberg-77576-full-license.txt").write_text(license_text, encoding="utf-8")
    rights = {
        "schema": 1,
        "resource": BOOK_ID,
        "sourceURL": SOURCE_URL,
        "projectGutenbergRecord": "https://www.gutenberg.org/ebooks/77576",
        "sourceFile": "resource-inputs/apostolic-fathers-77576.txt",
        "sourceSHA256": source_hash,
        "generatedJSONSHA256": sha256(out_bytes),
        "fullLicenseSHA256": sha256(license_text.encode("utf-8")),
        "accessed": "2026-10-28",
        "edition": "Edinburgh: T. & T. Clark, 1870; Ante-Nicene Christian Library, vol. I",
        "editors": ["Alexander Roberts", "James Donaldson"],
        "translators": ["Alexander Roberts", "James Donaldson", "Frederick Crombie"],
        "rightsStatement": "Public domain in the United States only; status may differ in other jurisdictions. The Project Gutenberg full license is reproduced verbatim alongside this resource.",
        "transformation": "Stdlib parser removes Project Gutenberg wrapper metadata, retains and labels the original printed contents and its 1870-edition page references, strips page-number-only lines, joins wrapped lines within paragraphs, retains source chapter/work headings, all other nonempty paragraphs, inline footnote markers, footnote blocks, editorial introductions, appendices, and indexes, and chunks long sections at paragraph boundaries. Adds source/use credits as the first reader article and the complete Project Gutenberg license as the final article. No summaries or external material are added.",
        "sourceParagraphsRetained": len(actual),
        "printedContentsRetained": True,
        "articleCount": len(articles),
        "articleIDsUnique": True,
    }
    (REFERENCE / "apostolic-fathers-rights.json").write_text(
        json.dumps(rights, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"articles": len(articles), "sourceSHA256": source_hash,
                      "resourceBytes": len(out_bytes), "resourceSHA256": sha256(out_bytes),
                      "licenseBytes": len(license_text.encode()),
                      "uniqueIDs": len(set(ids))}, indent=2))


if __name__ == "__main__":
    main()
