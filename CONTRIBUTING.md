# Contributing to Throughline

Start with a small problem you can describe and verify. Contributions can be code,
source corrections, resource research, translation, accessibility, testing or writing.
A Mac and paid AI accounts are not required for research or documentation work.

## First contribution

1. Check existing issues and [the roadmap](docs/ROADMAP.md). Open an issue describing
   the problem before a large change; small fixes can go straight to a pull request.
2. Fork the repository, create a branch, and keep the change focused.
3. Follow the [build instructions](README.md). For portable work, run
   `python3 scripts/test-suggestions.py` and `python3 scripts/test-public-resources.py`.
4. Explain the behavior before/after, relevant tests, and any limitations in the PR.
   Show light/dark screenshots for UI changes; redact personal material.
5. Respond to review asynchronously. No meeting, polished English, or theological
   agreement with every author in the library is required.

Please identify your contribution's language and use your preferred public name for
credit. Maintainers should help turn well-sourced reports into patches instead of
requiring every researcher to become a Swift developer. Avoid duplicate or huge PRs.

## Developer checks

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/verify-public-source.py
python3 scripts/test-suggestions.py
python3 scripts/test-public-resources.py
swift test
```

Tests use temporary stores and mock providers, never a contributor's notes or Keychain.
Optional live AI/provider tests are opt-in and must not become a PR requirement. Use
`STUDYTABLE_SNAPSHOT_DIR=/absolute/path swift test --filter SnapshotTests` to save
actual light/dark renders. See PUBLIC-SOURCE.md for withheld-corpus tests and importer
prerequisites. Passing tests do not prove historical accuracy or redistribution rights.

## Resource or theology changes

Identify the exact edition, translator, language, passage, stable source link, rights
notice and proposed change. Link copyrighted works; do not upload their full text.
Quote only what is necessary. Separate a translation from an author's other writings,
authorship from reception, disputed positions from documented council judgments, and
your interpretation from quoted evidence. State meaningful contrary evidence.

Generated resources should change through their generator and verified inputs. Do not
silently hand-edit snapshots or just refresh hashes to make a check green. Document
missing generator inputs and supply a licensed, pinned reproducible input before
changing that corpus. After review, update the snapshot manifest with
`python3 scripts/verify-public-source.py --write-manifest` and include its diff.

AI assistance is allowed. Disclose substantial generated content, verify it, and take
responsibility for the result. AI cannot be a reviewer, citation, rights clearance or
approval. Never use a contributor's private notes or credentials as model input.

## Reviews

Code and editorial reviews have different responsibilities; see GOVERNANCE.md. When
qualified reviewers are unavailable, a content claim remains pending. Escalation does
not automatically assign work to the founder. Avoid personal attacks or assumptions
about another contributor's beliefs. Corrections and appeals should carry evidence.

No contributor license agreement is required for this initial source contribution
workflow. Submit original code under the existing MIT license; third-party additions
must retain their actual license and attribution. Do not submit work you lack rights to.

CI runs correctness and rendering checks on shared runners. Absolute latency budgets
are opt-in on a physical Apple Silicon reference Mac; see docs/VALIDATION.md.
