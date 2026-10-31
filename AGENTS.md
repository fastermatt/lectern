# Thruline Bible contributor notes

- This is a native macOS SwiftUI app distributed as a public contributor beta.
- Keep the app fully useful offline and do not introduce a runtime AI dependency.
- Do not bundle copyrighted Bible translations without a written license.
- BSB is the bundled baseline. ESV/NKJV are optional reader-key online integrations; NASB is a licensed-pack slot.
- Preserve source provenance. Label exact quotations and editorial summaries distinctly.
- Thruline has no fixed confessional identity. The reader selects an alignment lens (Westminster Standards, Three Forms of Unity, ecumenical creeds, or none — default none); alignment claims must be sourced fact (agreement, tension, no mapping, or historically disputed with council + year), never an app-wide verdict, and never collapse "non-Reformed" into "heterodox." Westminster Confession chapter links (the separate curated-badge system) remain a transparent index, never a claim of universal agreement.
- Contrast views belong in an opt-in, clearly labeled area; never present them as the app's doctrinal conclusion.
- New UI must work in both light and fully dark appearance.
- Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every `swift` command (the CLT toolchain lacks the SwiftUI macro plugin).
- Resource snapshots are generated. Read PUBLIC-SOURCE.md for importer prerequisites; do not silently hand-edit snapshots. Run `scripts/verify-content.sh` before packaging. Never restore withheld HCF excerpts or candidate previews.
- WCF links: only human-reviewed (`state: curated`, named reviewer, date) links display. Never generate or auto-approve them; use `scripts/wcf-links.py`.
- ESV/NKJV are online-only with the user's own key and the publisher's caching limits (see `OnlineTranslations.swift`); never bundle them.
- The selected 2026-10-27 design removes rotary knobs; use compact reading controls and editable light/dark palettes. Selected state must not rely on colour alone.

