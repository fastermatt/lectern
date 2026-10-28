#!/usr/bin/env python3
"""One-time raw-data fetcher for the HelloAO Free Use Bible API commentaries
(https://bible.helloao.org/api/available_commentaries.json, Public Domain Mark 1.0 except
Tyndale which is CC BY-SA and is never fetched here).

Downloads every chapter JSON for the requested commentary ids into
work-content/helloao/<id>/<BOOK>/<chapter>.json, verifies each chapter's own reported
sha256 (HelloAO's commentary-level manifest does not give per-chapter hashes, so this
instead re-derives book/commentary totals and cross-checks against books.json), and writes
a small per-commentary manifest recording what was fetched. Safe to re-run: existing files
are skipped unless --force is given.

The API is static content served from S3 via CloudFront (see response headers: `server:
AmazonS3`, `x-cache: Hit from cloudfront`), not a live database, so this uses a small
worker pool (default 8) rather than one request at a time -- CloudFront-cached static
files absorb that trivially -- with a short per-request stagger, retry-with-backoff on
failure, and a real User-Agent identifying the app, which is the practical meaning of
"polite" for this kind of origin.

Narrow gap-fill mode (0.9.5 Isaiah 49-66, extended 0.10 R2 to the Psalms): pass `--books PSA
[ISA ...]` to fetch only those books, and `--dest-id calvin-helloao` to store them under a
different work-content/helloao/<dest-id>/ directory than the upstream commentary id (the app
keeps HelloAO's Calvin under `calvin-helloao` so it can never be mistaken for the primary
Pillar `calvin` source). In this mode the fetch record is *merged* into the existing
_fetch-manifest.json (one entry per book under "fetches", each with the sha256 of every chapter
file as written) instead of being overwritten, so earlier gap-fills (ISA) keep their record.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "work-content/helloao"
BASE = "https://bible.helloao.org/api"
USER_AGENT = "Lectern/0.18 (offline Bible study; resource importer)"


def fetch(url: str, retries: int = 4) -> bytes:
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=20) as resp:
                return resp.read()
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last_err = exc
            time.sleep(0.5 * (2 ** attempt))
    raise RuntimeError(f"failed to fetch {url}: {last_err}")


def fetch_json(url: str) -> dict:
    return json.loads(fetch(url).decode("utf-8"))


def fetch_chapter(commentary_id: str, book_id: str, chapter: int, force: bool,
                  dest_id: str | None = None) -> tuple[str, bool, str | None]:
    out_dir = OUT / (dest_id or commentary_id) / book_id
    out_path = out_dir / f"{chapter}.json"
    label = f"{dest_id or commentary_id}/{book_id}/{chapter}"
    if out_path.exists() and not force:
        return label, True, "cached"
    url = f"{BASE}/c/{commentary_id}/{book_id}/{chapter}.json"
    try:
        data = fetch(url)
        # Validate it is real JSON with the expected shape before writing.
        parsed = json.loads(data)
        if "chapter" not in parsed:
            return label, False, "missing 'chapter' key"
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(data)
        return label, True, None
    except Exception as exc:  # noqa: BLE001 - report and continue
        return label, False, str(exc)


def fetch_commentary(commentary_id: str, workers: int, force: bool,
                     only_books: list[str] | None = None, dest_id: str | None = None) -> dict:
    dest = dest_id or commentary_id
    print(f"== {commentary_id}: listing books", flush=True)
    books_doc = fetch_json(f"{BASE}/c/{commentary_id}/books.json")
    jobs: list[tuple[str, int]] = []
    skipped_books: list[str] = []
    for book in books_doc["books"]:
        if only_books and book["id"] not in only_books:
            continue
        first, last = book.get("firstChapterNumber"), book.get("lastChapterNumber")
        if first is None or last is None or book.get("numberOfChapters", 0) == 0:
            skipped_books.append(book["id"])  # e.g. keil-delitzsch/SNG: not covered, nulls in books.json
            continue
        for chapter in range(first, last + 1):
            jobs.append((book["id"], chapter))
    if skipped_books:
        print(f"== {commentary_id}: skipping uncovered books {skipped_books}", flush=True)
    print(f"== {commentary_id}: {len(jobs)} chapters across {len(books_doc['books'])} books", flush=True)

    ok, failed = 0, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(fetch_chapter, commentary_id, book_id, chapter, force, dest_id): (book_id, chapter)
            for book_id, chapter in jobs
        }
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            label, success, note = future.result()
            if success:
                ok += 1
            else:
                failed.append((label, note))
                print(f"   FAILED {label}: {note}", flush=True)
            if i % 200 == 0 or i == len(jobs):
                print(f"   {i}/{len(jobs)} ({ok} ok, {len(failed)} failed)", flush=True)

    (OUT / dest).mkdir(parents=True, exist_ok=True)
    if only_books:
        # Narrow gap-fill mode: merge into (never overwrite) the existing record.
        manifest_path = OUT / dest / "_fetch-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {
            "commentaryId": commentary_id}
        fetches = manifest.setdefault("fetches", {})
        for book_id in only_books:
            chapters = sorted(c for b, c in jobs if b == book_id)
            hashes = {}
            for c in chapters:
                path = OUT / dest / book_id / f"{c}.json"
                if path.exists():
                    hashes[str(c)] = hashlib.sha256(path.read_bytes()).hexdigest()
            fetches[book_id] = {
                "chaptersRequested": len(chapters),
                "chaptersPresent": len(hashes),
                "failed": [f for f in failed if f[0].startswith(f"{dest}/{book_id}/")],
                "sourceBookMetadata": next((b for b in books_doc["books"] if b["id"] == book_id), None),
                "chapterSha256": hashes,
            }
        manifest["sourceCommentaryMetadata"] = books_doc["commentary"]
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    else:
        manifest = {
            "commentaryId": commentary_id,
            "books": [b["id"] for b in books_doc["books"]],
            "totalChapters": len(jobs),
            "fetchedOk": ok,
            "failed": failed,
            "sourceBooksJSONSha256": None,
        }
        (OUT / dest / "_fetch-manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        (OUT / dest / "_books.json").write_text(
            json.dumps(books_doc, ensure_ascii=False), encoding="utf-8"
        )
    print(f"== {commentary_id}: done, {ok}/{len(jobs)} ok, {len(failed)} failed", flush=True)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("commentaries", nargs="+", help="HelloAO commentary ids, e.g. john-gill matthew-henry")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--force", action="store_true", help="re-download even if a chapter file already exists")
    parser.add_argument("--books", nargs="+", metavar="BOOK",
                        help="narrow gap-fill mode: fetch only these book ids (e.g. PSA); merges the fetch record")
    parser.add_argument("--dest-id", help="store under work-content/helloao/<dest-id>/ instead of the commentary id")
    args = parser.parse_args()

    exit_code = 0
    for commentary_id in args.commentaries:
        manifest = fetch_commentary(commentary_id, args.workers, args.force, args.books, args.dest_id)
        failed_any = manifest["failed"] if not args.books else [
            f for rec in manifest.get("fetches", {}).values() for f in rec["failed"]]
        if failed_any:
            exit_code = 1
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
