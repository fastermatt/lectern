#!/bin/zsh
# Build and package Thruline as an ad-hoc signed .app inside Releases/Thruline-Bible-<version>.zip.
# Refuses to overwrite an existing release: bump CFBundleShortVersionString/CFBundleVersion in Info.plist.
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$project_dir"


# iCloud sync-conflict guard (item 8, 0.7 fix batch): Sources/ lives inside a synced Documents
# folder, so "<name> N.ext" conflict-copy duplicates reappear under Resources on their own. Clean
# what's provably safe to remove (byte-identical to its original), then hard-fail packaging if
# anything matching that pattern is still present anywhere in Resources — a differing duplicate
# the cleaner declined to touch, or a fresh one iCloud wrote since. Never ships silently.
"$project_dir/scripts/clean-sync-duplicates.sh" || true
leftover_duplicates=$(find "$project_dir/Sources/StudyTable/Resources" -type f -regex '.* [0-9][0-9]*\.[^./]*$')
if [[ -n "$leftover_duplicates" ]]; then
  echo "error: iCloud sync-conflict duplicate files remain in Resources -- resolve them (see scripts/clean-sync-duplicates.sh output above) before packaging:" >&2
  echo "$leftover_duplicates" | head -10 >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
release_zip="$project_dir/Releases/Thruline-Bible-$version.zip"
if [[ -e "$release_zip" ]]; then
  echo "error: $release_zip already exists. Bump the version in Info.plist instead of overwriting a release." >&2
  exit 1
fi

# Resource files must not carry Finder/provenance attributes or codesign rejects the bundle.
xattr -cr Sources Assets Info.plist 2>/dev/null || true
# Always build from a clean scratch directory outside the synced Documents folder: SwiftPM's
# incremental product bundle keeps resources that were later removed from the source tree.
scratch="$(mktemp -d /private/tmp/study-table-build.XXXXXX)"
swift build -c "$configuration" --product StudyTable --scratch-path "$scratch"
bin_dir="$(swift build -c "$configuration" --show-bin-path --scratch-path "$scratch")"

temp_root="$(mktemp -d /private/tmp/study-table-package.XXXXXX)"
app_dir="$temp_root/Thruline Bible.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp Info.plist "$app_dir/Contents/Info.plist"
cp "$bin_dir/StudyTable" "$app_dir/Contents/MacOS/StudyTable"
cp scripts/lectern "$app_dir/Contents/MacOS/lectern"
chmod +x "$app_dir/Contents/MacOS/lectern"
cp scripts/thruline "$app_dir/Contents/MacOS/thruline"
chmod +x "$app_dir/Contents/MacOS/thruline"
cp -R "$bin_dir/StudyTable_StudyTable.bundle" "$app_dir/Contents/Resources/StudyTable_StudyTable.bundle"
cp Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
chmod +x "$app_dir/Contents/MacOS/StudyTable"
# Verify the pinned upstream runtime before copying or signing it.
python3 scripts/bootstrap-local-ai.py
python3 - <<'PYRUNTIME'
import hashlib, json
from pathlib import Path
root = Path('Vendor/LocalAI')
for item in json.loads((root / 'provenance.json').read_text())['files']:
    if hashlib.sha256((root / item['file']).read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit('Local AI runtime integrity check failed: ' + item['file'])
PYRUNTIME
mkdir -p "$app_dir/Contents/Helpers"
cp -R Vendor/LocalAI "$app_dir/Contents/Helpers/LocalAI"
xcrun clang -O2 -arch arm64 -mmacosx-version-min=14.0 scripts/local-ai-runner.c -o "$app_dir/Contents/Helpers/LocalAI/lectern-model-runner"
for helper in "$app_dir"/Contents/Helpers/LocalAI/*; do
  if [[ ! -L "$helper" ]] && file "$helper" | grep -q 'Mach-O'; then codesign --force --sign - "$helper"; fi
done

xattr -cr "$app_dir"

# Content guard: fail the package if raw build inputs or copyrighted translations slipped in.
resources="$app_dir/Contents/Resources/StudyTable_StudyTable.bundle"
if [[ -d "$resources/Contents/Resources" ]]; then
  resources="$resources/Contents/Resources"
fi
# Review rights at the actual distribution boundary. The developer corpus remains intact;
# public packages withhold HCF excerpts until exact editions are cleared for redistribution.
python3 scripts/prepare-public-resources.py "$resources"
python3 - "$resources" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
raw = (root / 'Reference/apostolic-fathers.json').read_bytes()
rights = json.loads((root / 'Reference/apostolic-fathers-rights.json').read_bytes())
book = json.loads(raw)
license_data = (root / 'Licenses/project-gutenberg-77576-full-license.txt').read_bytes()
if hashlib.sha256(raw).hexdigest() != rights['generatedJSONSHA256']:
    raise SystemExit('Patristic reader does not match its provenance record')
if hashlib.sha256(license_data).hexdigest() != rights['fullLicenseSHA256']:
    raise SystemExit('Patristic license does not match its provenance record')
if len(book['articles']) != rights['articleCount'] or not book['articles']:
    raise SystemExit('Patristic reader is empty or incomplete')
print(f"Verified included Apostolic Fathers reader: {len(book['articles'])} sections")
PY
forbidden=$(find "$app_dir" \( -iname '*.usfm' -o -iname '*.sqlite' -o -name 'mhcc.txt' -o -name '*.tsv' \
  -o -iname '*esv*' -o -iname '*nkjv*' -o -iname '*nasb*' -o -path '*pillar-commentary-data*' \) | head -5)
if [[ -n "$forbidden" ]]; then echo "error: forbidden files in the app bundle:\n$forbidden" >&2; exit 1; fi
bundled_duplicates=$(find "$resources" -type f -regex '.* [0-9][0-9]*\.[^./]*$')
if [[ -n "$bundled_duplicates" ]]; then
  echo "error: iCloud sync-conflict duplicate files made it into the built bundle:" >&2
  echo "$bundled_duplicates" | head -10 >&2
  exit 1
fi
for id in BSB KJV WEB; do [[ -f "$resources/Scripture/$id/manifest.json" ]] || { echo "error: missing $id pack" >&2; exit 1; }; done
study_books=$(find "$resources/Study" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$study_books" -eq 66 ]] || { echo "error: expected 66 study book directories" >&2; exit 1; }
[[ -f "$app_dir/Contents/Resources/AppIcon.icns" ]] || { echo "error: app icon missing" >&2; exit 1; }
echo "bundle contents verified: 3 public-domain packs, $study_books study book directories, no raw inputs"

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

mkdir -p "$project_dir/Releases"
cp BETA-TESTING.md "$temp_root/Start Here.md"
cp CLI-AND-AI.md "$temp_root/CLI-AND-AI.md"
cp WORKSPACE-AND-LIBRARY.md "$temp_root/WORKSPACE-AND-LIBRARY.md"
ditto -c -k --sequesterRsrc "$temp_root" "$release_zip"
echo "Packaged Thruline $version (build $build): $release_zip"
echo "Unzipped app for inspection: $app_dir"
