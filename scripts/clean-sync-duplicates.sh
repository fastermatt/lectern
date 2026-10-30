#!/bin/zsh
# iCloud sync-conflict cleanup (item 8, 0.7 fix batch). Because Sources/ lives inside an
# iCloud-synced Documents folder, editing the same underlying file from two devices/processes
# leaves macOS/iCloud "conflict copy" files behind, named "<original stem> N.<ext>" (e.g.
# "2 2.json" next to "2.json") — these keep reappearing on every sync pass and, left alone, get
# copied straight into the SwiftPM bundle as duplicate, dead resources.
#
# This script finds every "* N.ext" file under Sources/StudyTable/Resources and, for each one,
# deletes it ONLY when a same-named original (without the " N") exists AND is byte-identical
# (cmp -s) — i.e. only when it is provably a redundant copy, never a genuine variant. Anything
# that differs, or has no matching original at all, is reported and left untouched for a human to
# resolve; this script never guesses which version is "correct."
#
# Usage: scripts/clean-sync-duplicates.sh
# Exit code: 0 if every duplicate found was either removed or was already clean (no unresolved
# duplicates remain); 1 if any duplicate needed a human decision (differs from its original, or
# has no original at all) — those are reported but deliberately left in place either way.
set -uo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
# Keep generated folders out of iCloud sync (a folder swapped in wholesale loses the attribute).
"$project_dir/scripts/exclude-generated-from-icloud.sh"

resources="Sources/StudyTable/Resources"
# iCloud also leaves conflict *directories* ("Interlinear 2"). Remove only the EMPTY ones (rmdir
# refuses a non-empty directory, so this can never delete content); report any that hold files.
if [[ -d "$resources" ]]; then
  find "$resources" -depth -type d -name '* [0-9]' 2>/dev/null | while IFS= read -r conflict_dir; do
    find "$conflict_dir" -depth -type d -exec rmdir {} \; 2>/dev/null
    [[ -d "$conflict_dir" ]] && echo "CONFLICT DIRECTORY HAS CONTENT (left for human review): $conflict_dir"
  done
fi
if [[ ! -d "$resources" ]]; then
  echo "error: $resources not found (run from the Throughline Bible project root)" >&2
  exit 1
fi

removed=0
differing=0
no_original=0

# "* N.ext": a space, one or more digits, a dot, then the extension, right at the end of the
# filename. BSD find's -regex (no -E) doesn't support `+` as a quantifier, so `[0-9][0-9]*` spells
# "one or more digits" instead. Matched against the whole path, but the pattern only constrains
# the trailing filename, so it's equivalent to a basename match here.
while IFS= read -r -d '' dup; do
  base="${dup:t}"
  dir="${dup:h}"
  ext="${base##*.}"
  stem="${base%.*}"
  original_stem="${stem% [0-9]*}"
  if [[ "$original_stem" == "$stem" ]]; then
    # The strip above only removes a trailing " <digits>" run; if it did nothing, this file
    # somehow matched the find regex but not this stricter check — skip rather than guess.
    echo "SKIP (name didn't parse as '<original> N.ext'): $dup"
    no_original=$((no_original + 1))
    continue
  fi
  original="$dir/$original_stem.$ext"
  if [[ ! -f "$original" ]]; then
    echo "NO ORIGINAL (left in place): $dup  (expected $original)"
    no_original=$((no_original + 1))
    continue
  fi
  if cmp -s "$dup" "$original"; then
    rm -- "$dup"
    removed=$((removed + 1))
  else
    echo "DIFFERS FROM ORIGINAL (left in place for human review): $dup  vs  $original"
    differing=$((differing + 1))
  fi
done < <(find "$resources" -type f -regex '.* [0-9][0-9]*\.[^./]*$' -print0)

echo "iCloud duplicate cleanup: removed $removed byte-identical duplicate(s); $differing differing duplicate(s) left for review; $no_original with no matching original."

if [[ $differing -gt 0 || $no_original -gt 0 ]]; then
  exit 1
fi
exit 0
