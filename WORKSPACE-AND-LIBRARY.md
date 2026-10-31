# Thruline workspace and library

## Separate study windows

Use a pane's **Detach** icon (arrow out of a square), **View → Detach**, or the
**Study** menu to open Bible, Sources & tools, or Notes in its own native window.
Move, resize, minimize or place these windows on another display. Each pane has
one detached window; selecting Detach again brings that window forward.

Bible and Sources & tools follow the workspace's selected passage. Notes start
with **Pin note** on: the active note and its passage stay put while you browse
the Bible. Turn Pin note off to follow the workspace. Opening another saved note
from My Study or search selects that exact note in the existing Notes window.

**Return to workspace**, closing the window, or **View → Return all windows to
workspace** restores the panes. Returning pinned notes brings the Bible back to
the notebook's passage and retains its active note, template and unfinished draft.
Only one live notebook session and one StudyStore are used; no second notes file
or copied database is created. Changes made to the same saved note through another
study surface refresh the shared session. Existing backup/read-only alerts apply.

Window positions/sizes use macOS autosave. Since 0.22, separate windows that were
open when you quit reopen at their last position the next time Thruline starts.
Turn this off in **Layouts → Reopen separate windows when Thruline starts**.

Saved layouts include separate windows: which panes are detached, each window's
position and size, and whether Notes is pinned. Opening a layout opens its windows,
returns any other detached panes to the workspace, and keeps the layout's own passage
even when a pinned note pointed elsewhere. A startup layout's windows take priority
over the last session. Layouts saved before 0.22 open fully docked. A saved position
is used only when its title bar is still reachable on a connected display; otherwise
the window opens at its default place. Window recipes never contain note text.

This is pane detachment, not arbitrary tab groups or independent Bible/source
navigation sets.


## Reopening your notes

In **My Study → Notes**, choose a saved note and **Open in Reader** to reopen that
exact note and its saved template in the right-hand notebook. Search → Library &
notes → Open note in workspace uses the same route. The notebook and study desk
reopen even when hidden or in Reading focus. Notes attached to a passage range or
chapter are available while reading a verse inside that range. Previous/Next and
New in the notebook still let you choose among notes covering the current passage.

Version 0.20.2 fixes a navigation problem that could show a blank or different note
instead of the selected sermon note. This does not require recreating the note or
changing its template. If a note is visible in My Study, its saved content can be
read there before updating. Keep backups and use Recently Deleted for deliberately
deleted notes. User notes remain in the existing StudyTable support directory; the
fix does not migrate or replace the notes database.


## Guided passage study

Choose **Learn** in the toolbar or study desk. Four steps follow the selected verse:

1. **Read** shows the current translation and asks you to read its surrounding
   paragraph. Optional **Show emphasis notes** underlines the phrases discussed
   in a Thruline editorial observation. The initial examples are BSB Philippians
   4:4, John 20:28 and Ephesians 2:9. Other passages/editions explicitly show no
   note; highlighting requires matching BSB text. These are English-text
   observations, not a whole-Bible Greek/Hebrew emphasis dataset.
2. **Words** lets you choose an original word, see its gloss and available Strong's
   definitions, inspect textual variants and open its concordance. No inferred
   alignment to the English text is introduced.
3. **Grammar** adds plain-English lessons for six Greek verb features (aorist,
   present, imperfect, perfect, imperative and participle) and four Hebrew
   conjugations (perfect, imperfect, sequential imperfect and imperative). The
   same help appears in expanded original-word rows and single-word study. The
   initial lesson set does not cover every form or Aramaic. Unsupported forms
   retain source parsing and explicitly say that no teaching note is available.
   Repeated vocabulary is counted from non-variant noun/verb/adjective rows, not
   interpreted as proof of authorial emphasis.
4. **Reflect** saves what you type as a regular passage-linked note, tagged
   `lectern-guided-study`. Reopening the verse restores it. Existing unrelated
   notes are untouched; merely opening the guide creates no empty note. Notes
   warnings and read-only recovery still apply. The guide follows a single verse
   even if the reader has selected a range; its displayed anchor names that scope.

The included grammar explanations are adapted from unfoldingWord grammar under
CC BY-SA 4.0, with exact article links. Parsing/glosses retain STEPBible's CC BY 4.0
attribution; dictionaries retain their own notices. This is an initial teaching
set, without a claimed independent human linguistic review. It does not include
Discovery Bible's proprietary devotional lexicon, symbol system, annotations,
NASB text or software. It works offline; external reference links are optional.

## 0.17: Fathers & reception and navigation tips

**Library → Fathers & reception → Read** opens the included 1870 Apostolic Fathers volume. The reader offers a searchable table of contents and full-text search inside this volume; it is not yet verse-linked or part of global Library search. **Authors** opens 74 sourced profiles, including disputed reception and specific council/synod records. **Ideas & reception** is a reference area for sourced editorial comparisons, including modern Jungian readings and early disputes. These summaries do not automatically label imported books or imply complete writings for every profiled author.

**Appearance → Show navigation tips** controls optional hover guidance; the same switch exists in workspace settings. Preferences persist. Source warnings and accessibility labels are not switched off.


The default workspace is Bible, sources and notes. Search, Library, Add resources,
Your AI and Layouts are visible above the passage. The physical console keeps
a quiet metal rim and paper surfaces. There are no rotary dials or black status strip.

## Appearance and reading

Use the half-filled circle at the top right for **System**, **Light**, or **Dark**.
Choose Classic, Sage, Slate or Plum, or edit accent, page and text colors for each
finish separately. Choices save locally and update open windows. **Reset colors**
restores Classic without changing your type, notes, layouts or appearance mode.
The color editor keeps standard system control colors so Reset stays readable.

**Reading options** at the bottom controls Bible and study fonts, sizes and line spacing
independently. Existing preferences and pinch gestures are retained. **View** controls
pane visibility; **Reading focus** gives the Bible the full workspace.

Choose an entry in **Sources** to read its actual indexed text and provenance. At small
window sizes, the source list becomes a compact picker to leave room for reading and
notes. Source-bank filtering remains beside the linked-passage label; Guide and Tools
remain available as tabs. The sidebar chapter grid replaces the old fader.

## Make it your workspace

Open Layouts. Show or hide the Bible navigator, sources and notes; put the sources
on either side of the Bible. Drag the dividers, select your translation, passage,
source banks and study mode, then name and save the layout. Favorite, rename,
duplicate or delete a layout with its controls. Use **Update from current workspace**
to replace a saved arrangement and **Open at startup** for your preferred default.

Recipes include the passage/range, translation, source banks, tools/order, pinned
Guide range, pane visibility, reading/notes split fractions and Scripture size/leading.
The navigator stays within its existing compact width constraints. Layouts do not
copy notes, keys, AI conversations or books. Notes keep saving independently.
This is a fixed-role pane workspace with optional separate windows, not arbitrary
draggable tab groups or multiple independent link sets. Window minimums may constrain a saved divider fraction.

## Add free resources

Choose **Add resources**:

- Tyndale Open Study Notes: 16,923 passage notes plus 66 introductions, 66 summaries,
  125 profiles and 298 theme articles (17,478 text entries). Installed notes appear
  in Guide and Sources for matching passages, and can be read/searched in Library.
- Tyndale Open Bible Dictionary: 6,010 articles plus 110 textboxes. Text edition;
  maps, images, charts and original formatting are not reproduced.
- Nineteen optional eBible editions. English: ASV, YLT, Darby, Webster, Geneva 1599,
  Revised Version 1885 and Majority Standard Bible. Other languages: Reina Valera 1909,
  Ostervald, Louis Segond 1910, Luther 1912, Elberfelder 1905, Diodati, Riveduta,
  Kralická, Russian Synodal, Kulish (Ukrainian) and Chinese Union Version (simplified
  and traditional). Installed Bibles are available for offline reading/search/comparison.
- Church Fathers and classic Christian works (0.22): seventeen optional Project
  Gutenberg editions — Augustine (Confessions; City of God I–II; Donatist writings),
  Ambrose's letters, Chrysostom selections, Origen I–II (Ante-Nicene Christian
  Library), Hippolytus (Refutation of All Heresies I–II; Apostolic Tradition, Easton),
  Ayer's Source Book for Ancient Church History, Bede, Boethius, Calvin's Institutes
  I–II (Allen) and The Imitation of Christ (Benham). Add from Library → Fathers &
  reception or Free study resources; read and search offline. Gutenberg regenerates
  its files, so a byte checksum is not pinned: downloads use one HTTPS host, size
  limits, the safe EPUB reader and an expected-title match, and each install records
  the file's SHA-256 in its attribution. Bible references in them are linked (below).
- Suggestions before download (0.22): a bundled reference index (citations and section
  titles only, no text) lets the Study Desk list **Worth adding for this passage** —
  books you have not downloaded that discuss the passage, one per author first so less
  familiar voices surface — and lets Your AI recommend them.
- Notes and sources (0.22): **Sources** in the notebook lists where your library cites
  the passages in your note and paragraphs that share its key words. Your AI can read a
  note only when you choose Attach context → My open note.
- Linked and searchable texts (0.22): Bible references inside installed books and the
  included Apostolic Fathers ("Rom. viii. 28", "John 3:16", "1 Cor. xiii. 4–7") are
  detected and become links that open the passage. References inside numbered notes
  are traced back to the sentence carrying the note marker, and note markers jump to
  the note and back. The Study Desk's **From your library** panel lists every installed
  paragraph that cites the passage you are reading, with **Read in context**. Library
  search matches whole words in the same paragraph, lists exact phrases first, opens
  the reader at the matching paragraph with terms highlighted, and accepts a reference
  ("rev 20:4") to list the texts that cite it. Detection is automatic and conservative:
  chapter-only references are not linked, and older editions can use Latin or Greek
  Psalm numbering. Index-of-texts pages and bare unmatched notes are skipped.
- Fast ranked search (0.22): Library & notes search uses an on-device index built with
  macOS's own SQLite full-text engine (no extra software). It covers bundled commentaries,
  installed books, the Apostolic Fathers and downloaded historic works; notes are searched
  in memory and never indexed. Results are ranked by relevance, word forms match
  ("resurrection"/"resurrections"), exact phrases list first, and the result line shows
  the time taken. Commentary search went from about 15 s to under 0.1 s. The index is
  built quietly after launch (about 5 s the first time; later only new or changed books)
  and stores terms and locations only — no second copy of any text — about 120 MB in
  Application Support, ResourceBooks/.search-index.sqlite. Deleting it is safe; it rebuilds.
- Concept search (0.22): older writers rarely use modern terms, so a curated vocabulary
  widens a search to related wording — "rapture" also finds "caught up" and "meet the Lord
  in the air"; "millennium" finds "thousand years", "chiliasm", "millenarians"; "Antichrist"
  finds "man of sin". Results say what else was searched, and **Exact words only** turns
  it off. Widening a search is not a claim that two writers meant the same thing.
- Reading labels (0.22): each historic work carries a badge (for example "Doctor of the
  Church", "Disputed authorship", "Selections only"), era, genre, reading level, topics
  and sourced reading notes from a historian/theologian/ecumenical-editor review, with
  topic chips to filter. See docs/reviews/historic-works-labels-2026-10-31.md. Ideas &
  reception adds a sourced comparison of early chiliasm with pre-tribulation and
  Israel–church distinctives, reachable from the Darby notice.
- Historic works: the existing 74-work/volume EEBO-TCP catalogue, now searchable
  by author/title in a full-size Library window. Download and Open remain direct.

Tyndale downloads come from https://tyndaleopenresources.com/ and use CC BY-SA 4.0.
Thruline's text conversion is attributed and shares that license. Reviewed archive
checksums are pinned; a changed publisher file fails closed until the catalogue is
reviewed. No Matt account or API key is needed. Failed/cancelled installation does
not expose a partial book. Downloads are optional and are not bundled in the beta.

## Purchased or personal books

Library → Publisher stores links to The Good Book Company and Crossway. A click
opens their site; purchase and payment stay there. Check that the specific edition
provides an **unencrypted EPUB**. Then use **Import a book** to select that file.
UTF-8 text files are also supported. Imported books stay on your Mac and become
searchable. Import does not grant redistribution rights.

This text reader preserves the EPUB reading order and text, not images, original
pagination or page design. It rejects encrypted EPUBs and external XML entities;
it doesn't execute scripts or fetch web assets. It supports ZIP archives up to
30 MB, 500 members and 80 MB expanded. Complex/encrypted-font EPUBs may be rejected.
PDF, MOBI, Kindle and proprietary Logos formats are not supported in this release.

Publisher references:
- https://www.thegoodbook.com/ebook-faq
- https://www.crossway.org/faq/

## Search

Search has three tabs:

1. **Bible**: existing phrases, AND/OR/NOT, groups and prefix search, with scopes.
2. **Library & notes**: all entered words must occur in a commentary entry, book
   section or note. Includes downloaded Tyndale and TCP texts and personal imports.
   Filter by commentaries, books or notes; results include source details and
   passage navigation. Forty results per page, exact totals, cancellable background
   file scans. This is lexical search, not semantic AI search or a persistent FTS
   index. First/all-corpus searches take longer than Bible searches. Built-in
   dictionary/topic datasets keep their own study-tool search interfaces.
3. **Original languages**: exact lemma or Strong's number, language and grammar
   description/code. Try G26 + noun, or Greek + aorist active. Filters intersect;
   source edition/variant records count separately. Results navigate to the word's
   verse and reveal the original-language tool. Source: STEPBible, CC BY 4.0.

## How this maps to the requested Logos workflows

| Workflow | This candidate |
|---|---|
| Library search | Commentary, books, notes, Bible and morphology search; semantic/concept indexing still future work |
| Linked panels and layouts | Bible-linked sources/notes, pinned passage Guide, saved/favorite/startup recipes; no arbitrary tab docking or independent link sets |
| Sermon builder/manager | Existing note templates/projects/export remain; dedicated manuscript manager, service scheduling and slides still future work |
| Languages/comparison | New corpus morphology filters, existing word study/concordance and verse comparison; no syntax-tree or aligned pericope comparison |
| Notes/highlights | Existing anchored notes, highlights, collections and study-file transfer; no automatic cross-device sync |
| Print library | Not yet implemented. ISBN metadata alone cannot supply exact-page full-text search; licensed text or user-provided page indexes are required |

The workspace interaction was informed by Logos's public layout documentation:
https://support.logos.com/hc/en-us/articles/360016599631-Set-Up-Your-Workspace-with-Layouts
Thruline does not include Logos code, proprietary datasets, branding or entitlements.

Core study still works without AI. Your AI panel and read-only CLI remain available;
see CLI-AND-AI.md. The CLI intentionally continues to exclude personal books/notes.
The public 0.18.1 beta is ad-hoc signed and not Apple-notarized. See the
[installation guide](docs/INSTALL.md) and [public source](https://github.com/fastermatt/thruline-bible).
