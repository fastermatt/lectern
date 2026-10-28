# Passage-guide reference sources (Workstream J, 0.8)

Raw inputs cached here for reproducibility, mirroring `scripts/standards-sources/`.
`scripts/build-reference.py` only parses these cached files; it does not fetch anything.

## Nave's Topical Bible (1896, Orville J. Nave)

- **File:** `Nave.zip` — the official CrossWire SWORD module, downloaded from
  `https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/Nave.zip` (2026-09-23).
- **Licence evidence:** `nave.conf` (the module's own `mods.d` config, extracted verbatim
  into this folder) states `DistributionLicense=Public Domain` and
  `TextSource=https://ccel.org/ccel/n/nave/bible.xml`. CrossWire only ships works it has
  independently cleared for redistribution; this is the standard citation Bible software
  (Xiphos, BibleTime, AndBible, theWord-compatible tools) uses for Nave's.
- **Format:** SWORD "zLD" (compressed local dictionary) binary module — TEI-marked-up
  entries, one per topic, each a bag of `<ref osisRef="...">` verse citations (some grouped
  under `→ SUBHEADING` lines) and `<ref target="Nave:OTHERTOPIC">` cross-topic links.
  `scripts/build-reference.py` includes a small pure-Python zLD reader (`ZLDReader`), ported
  field-for-field from CrossWire's own reference Java implementation
  (`RawLDBackend.java`/`ZLDBackend.java`/`DataEntry.java` in `github.com/crosswire/jsword`,
  LGPL-2.1+, © CrossWire Bible Society) since no SWORD Python binding is available in this
  environment — the *format documentation* was ported, not GPL/LGPL code shipped in the app;
  the ~120-line Python reader is an independent reimplementation of a public binary layout.

## Easton's Bible Dictionary (1897, M.G. Easton)

- **File:** `Easton.zip` — the official CrossWire SWORD module, same mirror as above
  (`.../rawzip/Easton.zip`, 2026-09-23).
- **Licence evidence:** `easton.conf` states `DistributionLicense=Public Domain` and
  `TextSource=CCEL`. Same zLD format; read with the same `ZLDReader`.
- Book-introduction mapping (`Resources/Reference/easton/book-intros.json`) hand-verified
  against the actual headword list this build produced (all 66 canon books resolved to an
  exact Easton headword — see the build report's `easton.bookIntros` count).

## STEPBible TIPNR — Translators Individualised Proper Names with all References

- **File:** `TIPNR.txt` — `STEPBible-Data` repository,
  `Proper Nouns/TIPNR - Translators Individualised Proper Names with all References -
  STEPBible.org CC BY.txt`, fetched from
  `https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master/...` (2026-09-23).
- **Licence evidence:** the file's own header states **CC BY 4.0** explicitly ("STEPBible
  Data Repository **CC BY 4.0**... Data created initially by Tyndale House Cambridge now
  curated by www.STEPBible.org"), and the repository README repeats it. Required
  attribution (used verbatim in `Resources/Reference/meta.json` and the app's Settings/About
  screen): **"Proper names data from TIPNR, STEPBible.org (CC BY), Tyndale House Cambridge."**
- Each person/place's `@Briefest=`/`@Brief=`/`@Short=`/`@Article=` description tiers are
  STEPBible's own AI-drafted summaries (the repository's README says so directly: "Every
  individual has a description in brief, short and article length (created by Claude 3
  AI)") published by STEPBible itself under the same CC BY 4.0 licence as the rest of the
  file — this build uses `@Short=` (falling back to `@Brief=`/`@Briefest=`) as the compact
  description shown in the People & Places card, attributed to STEPBible like everything
  else from this file, never presented as Study Table's or Claude's own writing.
- The `EXCLUDED OTHER` category (STEPBible's own label) is dropped entirely — it holds
  general nouns like language names ("Latin") that STEPBible itself flags as not wanted in
  a proper-noun index.

## Per-verse index specificity (0.10, workstream R2)

`build-reference.py` ranks each verse's topics/headwords by the narrowest citing span (<= 10 verses, or
named in the verse's BSB text = direct; otherwise "wider passage"), caps the shown list (Nave 12,
Easton 8) and writes the remainder to `verse-index-more/`. The topic/article detail shards are
unchanged. See CONTENT-SOURCES.md, "Passage Guide reference indexes — specificity".
