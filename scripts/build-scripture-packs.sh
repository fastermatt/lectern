#!/bin/zsh
# Rebuild the compact Scripture packs from USFM sources. Deterministic: rerunning on
# unchanged input rewrites byte-identical files (see Tests: pack drift check).
#
#   scripts/build-scripture-packs.sh            rebuild the bundled BSB, KJV, WEB packs
#   scripts/build-scripture-packs.sh --check    fail if any bundled pack is stale
#   scripts/build-scripture-packs.sh --out <dir>
#       build the three bundled packs into <dir>/BSB, <dir>/KJV, <dir>/WEB (a staging area:
#       run twice and diff for byte-reproducibility, then rsync into Resources/Scripture).
#   scripts/build-scripture-packs.sh <usfm-dir> <out-dir> [--no-structure]
#       build one pack from your own USFM folder (which must contain translation.json),
#       e.g. a licensed ESV/NASB/NKJV pack for the app's Translations folder. Section
#       headings, parallel references and paragraph starts are kept unless --no-structure.
set -euo pipefail
project_dir="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$project_dir"
pack_scratch="${STUDYTABLE_PACK_SCRATCH:-/private/tmp/study-table-pack-check}"
swift build --product BuildScriptureIndex --scratch-path "$pack_scratch" >/dev/null
tool="$(swift build --show-bin-path --scratch-path "$pack_scratch")/BuildScriptureIndex"

if [[ $# -ge 2 && "$1" != --* ]]; then exec "$tool" "$@"; fi
flag="${1:-}"
dest="Sources/StudyTable/Resources/Scripture"
if [[ "$flag" == "--out" ]]; then dest="${2:?--out needs a directory}"; flag=""; fi
for pair in bsb:BSB kjv:KJV web:WEB; do
  "$tool" "scripture-source/${pair%%:*}" "$dest/${pair##*:}" ${flag:+"$flag"}
done
