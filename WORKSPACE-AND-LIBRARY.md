# Lectern 0.15.0 — passage study, layouts and your library

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
This is a fixed-role pane workspace, not arbitrary draggable tab groups or multiple
independent link sets. Window minimums may constrain a saved divider fraction.

## Add free resources

Choose **Add resources**:

- Tyndale Open Study Notes: 16,923 passage notes plus 66 introductions, 66 summaries,
  125 profiles and 298 theme articles (17,478 text entries). Installed notes appear
  in Guide and Sources for matching passages, and can be read/searched in Library.
- Tyndale Open Bible Dictionary: 6,010 articles plus 110 textboxes. Text edition;
  maps, images, charts and original formatting are not reproduced.
- Six optional eBible editions: ASV, YLT, Darby, Webster, Reina Valera 1909 and
  Ostervald. Installed Bibles are available for offline reading/search/comparison.
- Historic works: the existing 74-work/volume EEBO-TCP catalogue, now searchable
  by author/title in a full-size Library window. Download and Open remain direct.

Tyndale downloads come from https://tyndaleopenresources.com/ and use CC BY-SA 4.0.
Lectern's text conversion is attributed and shares that license. Reviewed archive
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
Lectern does not include Logos code, proprietary datasets, branding or entitlements.

Core study still works without AI. Your AI panel and read-only CLI remain available;
see CLI-AND-AI.md. The CLI intentionally continues to exclude personal books/notes.
This candidate is ad-hoc signed, not notarized or publicly published. Open-source
publication still needs the existing clean-source export and asset/license review.
