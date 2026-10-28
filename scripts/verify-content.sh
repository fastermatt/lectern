#!/bin/zsh
# One-shot content integrity gate: Scripture packs current, study indexes reproducible,
# Westminster store valid. Exits non-zero on the first problem.
set -euo pipefail
if [[ -f "${0:A:h:h}/PUBLIC-SOURCE.md" ]]; then
  cd "${0:A:h:h}"
  exec python3 scripts/verify-public-source.py
fi

project_dir="${0:A:h:h}"
cd "$project_dir"
# iCloud conflict copies (and a lost sync-exclusion) would corrupt the hashes below; clear them first.
"$project_dir/scripts/clean-sync-duplicates.sh" >/dev/null || true
echo "== Scripture packs"; scripts/build-scripture-packs.sh --check
echo "== Study indexes reproducible"
before=$(find Sources/StudyTable/Resources/Study -name '*.json' -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)
python3 scripts/build-study-resources.py >/dev/null
after=$(find Sources/StudyTable/Resources/Study -name '*.json' -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)
[[ "$before" == "$after" ]] && echo "study indexes: byte-identical rebuild" || { echo "STALE: committed study indexes differ from a fresh build"; exit 1; }
echo "== Westminster links"; python3 scripts/wcf-links.py validate
echo "== Apostolic Fathers reader reproducible"
python3 - <<'PY'
import hashlib, subprocess
from pathlib import Path
paths = [Path('Sources/StudyTable/Resources/Reference') / n for n in
         ('apostolic-fathers.json', 'apostolic-fathers-rights.json')]
paths.append(Path('Sources/StudyTable/Resources/Licenses/project-gutenberg-77576-full-license.txt'))
before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
subprocess.run(['python3', 'scripts/build-patristic-reader.py'], check=True, stdout=subprocess.DEVNULL)
after = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
if before != after:
    raise SystemExit('STALE: Apostolic Fathers reader differs from its pinned source rebuild')
print('Apostolic Fathers reader, rights and license: byte-identical rebuild')
PY
