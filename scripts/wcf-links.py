#!/usr/bin/env python3
"""Review tooling for the curated Westminster Confession link store.

    wcf-links.py validate                      check the store against the generated indexes
    wcf-links.py queue --book ROM --chapter 8  list entries (with stable IDs) a reviewer can link
    wcf-links.py add ENTRY_ID --wcf 8.5 --relation affirms --reviewer "Name" [--state curated] [--note ...]

A link says a *named human reviewer* judged that a specific source excerpt bears on a specific
WCF chapter/section. Being a Reformed source is never enough; nothing here is generated
automatically, and only state=curated links (with reviewer and date) are shown by the app.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STUDY = ROOT / "Sources/StudyTable/Resources/Study"
CONF = ROOT / "Sources/StudyTable/Resources/Confession"
LINKS = CONF / "wcf-links.json"
STATES = {"candidate", "curated", "rejected"}
RELATIONS = {"affirms", "discusses", "qualifies"}


def load_chapters() -> dict[int, dict]:
    doc = json.loads((CONF / "wcf-chapters.json").read_text(encoding="utf-8"))
    return {c["n"]: c for c in doc["chapters"]}


def load_entries() -> dict[str, dict]:
    # Resources/Study/<CODE>/<CHAPTER>.json (per-chapter, since 0.7 -- see StudyResourceStore's
    # doc comment for why: a monolithic per-book file made the largest books too slow to decode
    # on a cold book switch once Gill/Henry Complete were added).
    entries: dict[str, dict] = {}
    for path in sorted(STUDY.glob("*/*.json")):
        for item in json.loads(path.read_text(encoding="utf-8"))["entries"]:
            entries[item["id"]] = item
    return entries


def validate() -> int:
    chapters, entries = load_chapters(), load_entries()
    doc = json.loads(LINKS.read_text(encoding="utf-8"))
    errors: list[str] = []
    seen: set[tuple] = set()
    for index, link in enumerate(doc["links"]):
        where = f"link[{index}] {link.get('entryID', '?')}"
        entry = entries.get(link.get("entryID", ""))
        if entry is None:
            errors.append(f"{where}: entry ID not found in generated indexes (orphaned or stale)")
        elif entry["tradition"] == "Cross-References":
            errors.append(f"{where}: cross-reference lists are not doctrinal statements and cannot carry WCF links")
        ref = link.get("wcf", {})
        chapter = chapters.get(ref.get("chapter"))
        if chapter is None:
            errors.append(f"{where}: unknown WCF chapter {ref.get('chapter')!r}")
        elif ref.get("section") is not None and not 1 <= ref["section"] <= chapter["sections"]:
            errors.append(f"{where}: WCF {ref['chapter']} has {chapter['sections']} sections, not {ref['section']}")
        if link.get("relation") not in RELATIONS:
            errors.append(f"{where}: relation must be one of {sorted(RELATIONS)}")
        if link.get("state") not in STATES:
            errors.append(f"{where}: state must be one of {sorted(STATES)}")
        if link.get("state") == "curated":
            if not (link.get("reviewer") or "").strip():
                errors.append(f"{where}: curated links require a named reviewer")
            try:
                datetime.date.fromisoformat(link.get("reviewedOn", ""))
            except ValueError:
                errors.append(f"{where}: curated links require reviewedOn as YYYY-MM-DD")
        key = (link.get("entryID"), ref.get("chapter"), ref.get("section"))
        if key in seen:
            errors.append(f"{where}: duplicate link")
        seen.add(key)
    counts = {s: sum(1 for l in doc["links"] if l.get("state") == s) for s in sorted(STATES)}
    print(f"{len(doc['links'])} links {counts}; {len(errors)} problems")
    for error in errors:
        print("  ERROR", error)
    return 1 if errors else 0


def queue(args) -> int:
    entries = load_entries()
    shown = 0
    for item in entries.values():
        if item["tradition"] == "Cross-References" or not item["id"].startswith(f"{args.book}."):
            continue
        if args.chapter and item["chapter"] != args.chapter:
            continue
        if args.verse and not item["startVerse"] <= args.verse <= item["endVerse"]:
            continue
        preview = item["excerpt"][:110].replace("\n", " ")
        print(f"{item['id']}  {item['author']} vv.{item['startVerse']}-{item['endVerse']}  {preview}…")
        shown += 1
    print(f"{shown} entries")
    return 0


def add(args) -> int:
    entries, chapters = load_entries(), load_chapters()
    entry = entries.get(args.entry)
    if entry is None:
        print("unknown entry ID", file=sys.stderr)
        return 2
    chapter_text, _, section_text = args.wcf.partition(".")
    link = {
        "entryID": args.entry,
        "wcf": {"chapter": int(chapter_text), "section": int(section_text) if section_text else None},
        "relation": args.relation,
        "state": args.state,
        "excerptPreview": entry["excerpt"][:80],
    }
    if args.state == "curated":
        link["reviewer"] = args.reviewer
        link["reviewedOn"] = datetime.date.today().isoformat()
    if args.note:
        link["note"] = args.note
    doc = json.loads(LINKS.read_text(encoding="utf-8"))
    doc["links"].append(link)
    doc["links"].sort(key=lambda l: (l["entryID"], l["wcf"]["chapter"], l["wcf"]["section"] or 0))
    LINKS.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return validate()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate")
    q = sub.add_parser("queue")
    q.add_argument("--book", required=True)
    q.add_argument("--chapter", type=int)
    q.add_argument("--verse", type=int)
    a = sub.add_parser("add")
    a.add_argument("entry")
    a.add_argument("--wcf", required=True, help="chapter or chapter.section, e.g. 8.5")
    a.add_argument("--relation", required=True, choices=sorted(RELATIONS))
    a.add_argument("--state", default="candidate", choices=sorted(STATES))
    a.add_argument("--reviewer", default="")
    a.add_argument("--note", default="")
    args = parser.parse_args()
    return {"validate": lambda: validate(), "queue": lambda: queue(args), "add": lambda: add(args)}[args.cmd]()


if __name__ == "__main__":
    sys.exit(main())
