# Source preparation checks — 2026-10-28

## 0.20.2 note reopening fix — 2026-10-30

Two native-editor regression tests first failed on 0.20.1: opening a specific
sermon note showed another note at the same verse, and opening a range note
showed a blank editor. The old open-note notification had no notebook subscriber;
the search route also retained only a passage instead of the note identity.

The final affected suite passes 75 tests with zero failures, including seven
native-editor/navigation regressions, notebook light/dark renders, notes-store
recovery, guided reflections and workspace/search behavior. Requests now survive
a hidden notebook, repeated opens select the exact note, and paragraph/chapter
notes are visible from their contained verses. Tests verify that native typing
is persisted before a passage change, reopening leaves all saved note fields
unchanged, and invalid/deleted requests do not navigate. Test data is ephemeral;
no real user notes were read, changed or recovered during these checks.

The snapshot/content gate and all ten portable Python tests pass. No notes-file
schema, data-directory, backup or migration changes are introduced. This fixes
reopening and display behavior; it is not a claim of forensic recovery from a
reader's actual Mac. Hosted full-suite results belong to the release PR.

This historical validation record covers the public-source preparation of the former Lectern 0.18.0. The current Throughline Bible repository is https://github.com/fastermatt/throughline-bible. This document records local
checks; consult the Actions tab for current hosted results. An independent contributor
Mac is still needed for installation testing.

- Clean exported source compiled locally with full Xcode/Swift 6.4 on Apple Silicon.
  A separate Git clone also built and ran its focused verification suite without
  private files, downloaded models, runtime binaries or maintainer credentials.
  That fresh-clone run completed 61 tests: 57 passed, 4 opt-in/corpus audits skipped,
  zero failures. The clean source light/dark screenshot test also passed.
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
The reviewed repository is now published; private development history remains excluded.

## Hosted runner portability and performance

Snapshots use a fixed 2x bitmap, independent of physical display scale. The verse text
comparison excludes selection styling, which intentionally changed in the redesign.
The full optimized local run passed: 630 tests, 13 explicit opt-in/withheld-corpus skips,
zero failures. All affected visual checks subsequently passed on the hosted runner.

The shared runner exceeded absolute latency budgets even with optimization (2,020ms
for first interlinear concordance vs a 500ms target), and the optimized build plus suite
hit the 30-minute timeout. CI therefore runs the debug correctness/rendering suite;
it always checks actual lookup results and records latency, but does not claim to
certify physical-machine performance. Offscreen windows release their content after
capture instead of retaining study state between renders.

Before a release, explicitly enforce the unchanged 50ms/500ms budgets on a physical
Apple Silicon reference Mac with full Xcode selected:

```sh
LECTERN_ENFORCE_PERFORMANCE_BUDGETS=1 swift test -c release --filter 'InterlinearTests|LexiconTests'
```

Record hardware, build configuration and results. Do not interpret passing shared-runner
CI as meeting these performance targets. New contributors can run the same opt-in check;
when reporting a regression include machine/OS/build details, not private user data.

## 0.19.0 guided-study candidate — 2026-10-28

Local debug regression passed 639 tests, 11 explicit skips, zero failures. After
the final narrow-pane step-grid correction and reflection editor identity guard,
the focused grammar/passage-learning/rendering run passed 10 tests, zero failures.
The full suite was not repeated after those small changes. Eight final 330-point
light/dark renders cover Read, Words, Grammar and Reflect; the step grid, text,
emphasis underline and native controls were visually inspected. No independent
human linguistic review or hands-on second-Mac installation is claimed.

Coverage includes Hebrew fused-morpheme parsing and sequential forms, Greek
imperfect/perfect separation, unsupported forms/languages, real tagged verbs,
BSB-only emphasis phrase guards, repeated vocabulary, reflection reload without
overwriting other notes, empty-note prevention and read-only rejection. The
public resource snapshot gate passes with 3,306 files and unchanged 98,831 study
entries; the sole new bundled resource is the grammar attribution notice.

The beta is ad-hoc signed, Apple Silicon/macOS 14+, without notarization or an
automatic updater. The teaching set has ten general grammar lessons and three
BSB editorial emphasis examples, not Discovery Bible content or full parity.
