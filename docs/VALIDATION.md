# Source preparation checks — 2026-10-28

This repository is a public-source preparation based on Lectern 0.18.0. It has not
been pushed to GitHub; hosted CI and a second contributor machine are not yet verified.

- Clean exported source compiled locally with full Xcode/Swift 6.4 on Apple Silicon.
  A separate Git clone also built and ran its focused verification suite without
  private files, downloaded models, runtime binaries or maintainer credentials.
- Initial 630-test run identified 15 failures caused by withheld-corpus assumptions,
  omitted internal documentation and two orphaned HCF candidate link previews.
  The previews were removed; tests now use explicit public expectations/synthetic
  behavior fixtures. Four historical HCF corpus audits are explicitly skipped.
- All affected groups reran: 110 tests, 4 skipped, 0 failures (106 passed).
  Unaffected tests had passed in the initial full run. This is not represented as a
  second complete 630-test run after corrections.
- Public snapshot validator covers 3,305 resource/input files and 98,831 study entries,
  rejects HCF entries and candidate previews, and verifies patristic text/notice hashes.
- Six public-resource gate tests and four portable contribution tests passed.
- Pinned local-engine bootstrap downloaded/verified the official archive and built
  the parent-watching launcher on this Mac. Model inference was exercised in the
  preceding 0.18.0 beta work; default source CI deliberately does not download models.
- Gitleaks v8.30.1 redacted credential scan: no findings. A separate privacy review
  found and removed one personal email in a fetch script. Test-only URL credentials
  remain as clearly synthetic negative-validation fixtures; they are not real keys.
- Private development history, research notes, releases, models, unreviewed texture
  and mixed-rights raw inputs are excluded. This does not certify the original private
  folder, machine, vault or their histories as secret-free.

Before uploading, review the staged tree/history and docs/RELEASING.md. Before publishing
an app release, run the source checks again, package it, test a clean second Mac, and
state signing/notarization status. Source MIT licensing does not relicense third-party
resource content. Complete from-upstream regeneration is still a documented follow-up.

Final Git preparation: no tracked file exceeds GitHub's 100 MB limit. Snapshot
line endings are preserved with .gitattributes for Windows/Linux contributors.
Known private contact comparisons and personal-path checks returned no matches.
The repository has newly created history with a generic automation author identity.
No GitHub remote is configured and no source has been uploaded.
