# Standards sources — provenance and licence evidence

Workstream B (Confessional standards & proof texts), 2026-09-22. Every raw file this
records lives in `scripts/standards-sources/raw/` and is read only by
`scripts/build-standards.py` (never edited by hand — if a source needs to change, refetch
and re-run the build). This file is the licence-gate paper trail the project's ground
rules require before anything ships.

## Candidate source rejected in part: NonlinearFruit/Creeds.json

Checked directly (README + `metadata/`, not just GitHub's licence detector, which shows
nothing): the repo's own README states *"This repo as a whole is not licensed for reuse
due to the copyright status of several texts... These documents aside, the rest of this
repo is licensed under the Unlicense."* None of the six documents below are on its
named-exception list, so the Unlicense covers nlf's own compilation/structuring of them —
but that says nothing about whether the underlying *translation* each document uses is
itself public domain, which had to be checked per document (see below). Two of the six
turned out to use a translation that is **not** public domain, and were sourced
elsewhere instead:

- **Belgic Confession** — nlf's text is verbatim the Christian Reformed Church's
  official `BelgicConfession.pdf` (`crcna.org`), confirmed by a direct line-for-line
  diff (both read "a single and simple spiritual being" / "the Creation and Fall of
  Humanity"). That translation is explicitly copyrighted: search results for it return
  *"The English translation is copyrighted by Faith Alive Christian Resources and was
  approved by Synod 2011 of the Christian Reformed Church... Except for study,
  education, review, or worship use up to 100 copies, no part of this resource may be
  reproduced in any manner whatsoever without written permission from the publisher."*
  **Rejected.** Sourced from Schaff instead (below).
- **Heidelberg Catechism** — nlf's wording ("belong with body and soul, both in life
  and in death, to my faithful Saviour Jesus Christ") matches neither the clearly-PD
  archaic translation (below) nor the clearly-modern CRC 2011 translation ("belong—body
  and soul, in life and in death—to my faithful Savior") closely enough to be confident
  either way, and its own `SourceAttribution: "Public Domain"` is nlf's unverified
  claim, not independent evidence. Per the project's own stated policy ("if a document
  uses a modern copyrighted translation, source from a public-domain edition instead"),
  treated as unverified and **not used**. Sourced from CCEL instead (below).

**Westminster Confession, Larger Catechism, Shorter Catechism, and Canons of Dort's
positive Articles** all checked out: nlf's own metadata cites a specific archive.org
scan of the original 1647 Assembly printing (`SourceAttribution: "Public Domain"`,
`SourceUrl` given), and independent verification (below) confirms the text is the
genuine 1647/1619 wording, not a modern paraphrase. Used, with the caveats noted below.

## Per-document sourcing, translation, and licence

### Westminster Confession of Faith (`wcf`)

- **Structure/wording**: American revision, scraped from `opc.org/wcf.html` (the same
  edition `wcf-chapters.json`'s own structure was checked against — confirmed by an
  automated section-count comparison against every one of the 33 chapters: all match,
  including the one genuine structural difference from the original, WCF 31 (5 sections
  → 4). Public domain: a 17th/18th-century ecclesiastical confession, published by OPC
  as its own doctrinal standard without a copyright notice or restriction.
- **Proof texts**: the historic 1647 Assembly's own citations, from
  `scripts/standards-sources/raw/wcf-1647-nlf.json` (nlf, sourced from an archive.org
  scan of *The Humble Advice of the Assembly of Divines... with the Quotations and
  Texts of Scripture Annexed*, public domain).
  **Cross-checked against a second, independent source** —
  `thewestminsterstandard.org/the-westminster-confession/` — for the exact fact the
  workplan asked to verify: WCF 3.5 cites Rom 8:30; WCF 3.6 cites Rom 8:28-39 and Rom
  8:30. Confirmed verbatim on both sites (see
  `raw/wcf-original-thewestminsterstandard.txt`, chapter III, sections V-VI).
- **Alignment**: the American revision's wording differs from 1647 in a small, well
  documented set of places (chapters 20, 23, 24, 25, 31 — civil-magistrate and
  church/state provisions). `build_wcf()` aligns each of the 171 American sections to
  its 1647 counterpart by text similarity (threshold 0.75) and carries the historic
  proof text over only where the wording substantially matches. **3 sections did not
  match** (were genuinely rewritten by the American revision) and carry **no** proof
  text rather than an invented one: WCF 23.3 (civil magistrate's ecclesiastical
  authority), WCF 25.6 (the "Pope is antichrist" clause, removed), WCF 31.1 (synods'
  authority to convene, reworded). This is reported in `build-report.json`, not hidden.
- One further built-in correction: WCF 1.2 (the list of 66 canonical books) is taken
  directly from the 1647 text rather than scraped from OPC's page — OPC's page renders
  that list from a 3-column HTML table that collapses into garbled reading order once
  HTML tags are stripped; the book list itself is identical in substance either way.

### The Larger Catechism (`wlc`) and The Shorter Catechism (`wsc`)

- Both: original 1647 Assembly Q/A text, `raw/wlc-1647-nlf.json` /
  `raw/wsc-1647-text-nlf.json` (nlf, archive.org 1647 scans, public domain). 196
  questions / 107 questions confirmed.
- WLC's proof texts are nlf's own (already present in that same PD source).
- WSC's Assembly Q/A text does **not** carry proof texts in nlf's file (the Shorter
  Catechism's proofs were historically annexed separately, at Parliament's request, in
  1648) — proofs are read instead from `thewestminsterstandard.org`'s WSC page
  (`raw/wsc-proofs-thewestminsterstandard.html`), matched to each of the 107 nlf
  questions by locating the first Scripture-citation-shaped token following that
  question's own answer text. Same 1647/1648 Assembly text; public domain.

### Heidelberg Catechism (`hc`)

- Traditional public-domain English translation — matched **word for word,
  independently, at two separate sites**: `www.ccel.org/creeds/heidelberg-cat.html`
  (used as the parse source, `raw/heidelberg-ccel.html`) and
  `thewestminsterstandard.org/heidelberg-catechism/`
  (`raw/heidelberg-thewestminsterstandard.html`, cross-check only — Q1 confirmed
  verbatim on both). Archaic diction throughout ("thy", "sincerely willing and ready,
  henceforth, to live unto him") that is textually distinct from the modern
  1975/1988/2011 CRC & RCA joint translation (copyrighted by Faith Alive Christian
  Resources; reads "belong—body and soul, in life and in death—to my faithful Savior,
  Jesus Christ"). 129 questions / 52 Lord's Days confirmed. Its own lettered
  Scripture-proof apparatus, present on the page, supplies the proof texts (3
  legitimately proof-less questions — 24, 68, 83, purely organizational/enumerating
  answers — plus Q23, the bare Apostles' Creed recitation, none of which the historic
  apparatus attaches a citation to either).

### The Belgic Confession (`bc`)

- **Text**: the Reformed (Dutch) Church in America's 19th-century authorized English
  translation, read from `thewestminsterstandard.org/the-belgic-confession/`
  (`raw/belgic-confession-thewestminsterstandard.txt`) — chosen for being cleanly
  single-language (Schaff's edition, below, is French/English interleaved by printed
  column and not safely separable by an automated script). Verified as the *same*
  translation as Schaff's by direct comparison of Article 1 and the closing Article 37
  wording (both read "one only simple and spiritual Being" / "By the same token" style
  archaic diction — not the CRC 2011 wording rejected above).
- **Proof texts**: primarily Philip Schaff, *Creeds of Christendom*, vol. III (1877;
  Baker 1889 reprint), `raw/belgic-confession-schaff.txt` — the full French/English
  bilingual text **with its footnoted Scripture-proof apparatus** (316 footnotes across
  the 37 articles), fetched from CCEL's plain-text export of the whole volume
  (`https://ccel.org/ccel/s/schaff/creeds3/cache/creeds3.txt`), whose own header
  explicitly states **`Rights: Public Domain`**. `build_belgic()` locates each
  footnote-marker number that falls within an article's span (the markers only ever
  appear on the French side of the printed page, but the numbers themselves are
  language-agnostic, so this never needs to separate French from English) and resolves
  each to its definition in the footnotes block, without needing the interleaved
  bilingual text for anything else. This gave real depth: 34 of 37 articles carry at
  least one proof text (up from 3 of 37 using only the prose citations written directly
  into the thewestminsterstandard.org text, which are also kept and merged in). The 3
  articles with none (4, 5, 6 — Scripture's canonicity, authority, and the
  canonical/apocryphal distinction) are general-principle articles the source itself
  does not attach a specific proof text to.
- One known, reported (not corrected) defect in the 1877/1889 source text itself:
  footnote [473] reads "1 Pier. 23" with no chapter numeral — almost certainly a
  dropped "i." (1 Peter 1:23 fits the context, regeneration "by the word of God"), but
  guessing the correction risks fabricating a citation, so it is dropped and logged
  (`build-report.json` warnings) rather than silently invented or silently kept wrong.

### Canons of Dort (`cd`)

- **Positive Articles**: the same Reformed (Dutch) Church in America translation Schaff
  reprinted (public domain, per above) — verified word-for-word identical between
  `raw/canons-of-dort-nlf.json` (nlf) and Schaff's own reprint
  (`raw/belgic-confession-schaff.txt`'s neighbor in the same volume; not separately
  cached since nlf's copy is already confirmed identical and is the one actually
  parsed).
- **Rejection of Errors — WITHHELD from 0.7.0, not shipped.** nlf's Rejection-of-Errors
  sections are **not** present in Schaff's abridged RCA reprint (his own editorial note
  explains the RCA's Constitution prints only the positive Articles, omitting Preface,
  Conclusion, and the Rejection of Errors). The only source found for this text was the
  United Reformed Churches in North America's own published confessional-standard page
  (`urcna.org/urcna/confessionshtml/canonshtml/`) — word-for-word identical to nlf's
  Rejection-of-Errors wording — with **no copyright notice or reproduction restriction
  found**. On reflection this is **not enough to ship under ground rule 6** ("if a
  source is unclear, do not ship it — report it"): an absent copyright notice is not a
  positive public-domain declaration, and the wording itself reads like the
  mid-20th-century CRC Psalter Hymnal rendering of the Canons, whose actual US
  copyright/renewal status this workstream could not confirm either way. `build_canons()`
  in `scripts/build-standards.py` still *parses* the 34 Rejection-of-Errors items (so the
  code isn't lost, and re-enabling them is a one-line change once a document with
  positive PD evidence is found) but never emits them into `cd.json` or the reverse
  index — see that function's own long comment. Candidate replacements for a future
  pass, to be verified with the same positive-evidence standard used for the Articles:
  Thomas Scott's 1818 English translation of the Acts of the Synod of Dort (pre-1929,
  unambiguously PD, includes the Rejection of Errors in full), or any other verified
  pre-1931 US edition.
- **Proof texts**: this translation's own inline Scripture quotations/citations —
  unlike the Westminster/Heidelberg lettered-footnote apparatus, the Canons of Dort's
  historic English text argues directly from quoted Scripture inline ("according to the
  words of the Apostle (Rom. iii. 19), 'that every mouth may be stopped...'"), so the
  inline citations *are* its proof-text apparatus; extracted by the same reference
  parser used everywhere else. Of the 59 Articles shipped, those carrying at least one
  citation are recorded in `build-report.json` (`documents.cd.itemsWithProofs`); the
  rest are doctrinal argument without a directly quoted verse in this particular
  translation, not a parsing gap (spot-checked).
- **Found and fixed a real defect in nlf's own head numbering**: nlf labels the Fifth
  Head of Doctrine ("Of the Perseverance of the Saints") `"Chapter": "4"` — a straight
  duplicate of the Third-and-Fourth Head's own `"4"` component, which every standard
  reference to the Canons numbers as the *Fifth* Head. `build_canons()` corrects this to
  `"5"` before building item IDs, so citations read `Canons of Dort 5.A1`, not a second,
  colliding `4.A1`. Final head set: `1`, `2`, `3&4`, `5`.

## Reference parser and the BSB canon-bounds check

`scripts/build-standards.py`'s `parse_references()` handles OSIS-style dotted refs
(`Rom.8.30`), classic English abbreviations with colons (`Rom. 8:30`), Schaff's
roman-numeral-chapter French/English footnote style (`Eph. iv. 5`), comma/semicolon
lists, same-chapter ranges, cross-chapter ranges, and whole-chapter citations with no
verse (`Exod.21`, expanded to every verse of that chapter). Every resolved reference is
checked against the bundled BSB canon's actual verse counts
(`Resources/Scripture/BSB/manifest.json`) before being added to the reverse index; a
reference that doesn't resolve (either a genuine cross-edition versification difference,
e.g. Matt 18:35 — the BSB's chapter 18 only reaches verse 34 — or a source-text defect,
e.g. "Gal. xxx. 15" in the Schaff excerpt, where Galatians has 6 chapters) is **reported
in `build-report.json`, not silently dropped from the document text and not silently
omitted from the report**. 17 such mismatches are recorded for this build; none are
errors in this pipeline's own logic (each was individually traced to its raw source
line and quoted above or in `build-report.json`).

## Regenerating

```
python3 scripts/build-standards.py            # writes Resources/Confession/standards/*.json
python3 scripts/build-standards.py --report-only  # prints the report to stdout, writes nothing
```

Deterministic: two runs on the same `raw/` inputs produce byte-identical output
(verified by diffing two consecutive runs during this build).
