#!/bin/bash
# Publish a packaged Thruline build as a GitHub release that the in-app updater can install.
#
#   scripts/publish-release.sh Releases/Thruline-Bible-0.23.0.zip notes.md [--final]
#
# Signs the ZIP with the release key in your Keychain (scripts/release-key.swift), verifies the
# signature against the key compiled into the app, writes the .sha256, and uploads all three assets.
# Releases are marked pre-release unless --final is given. Requires `gh auth login`.
set -euo pipefail
cd "$(dirname "$0")/.."
zip="${1:?usage: publish-release.sh <zip> <notes.md> [--final]}"
notes="${2:?usage: publish-release.sh <zip> <notes.md> [--final]}"
[[ -f "$zip" && -f "$notes" ]] || { echo "error: missing $zip or $notes" >&2; exit 1; }
version=$(basename "$zip" .zip | sed -E 's/^Thruline-Bible-//')
tag="v${version}"
plist_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
[[ "$plist_version" == "$version" ]] || { echo "error: Info.plist says $plist_version but the ZIP is $version" >&2; exit 1; }

swift scripts/release-key.swift sign "$zip"
swift scripts/release-key.swift verify "$zip"
(cd "$(dirname "$zip")" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

flags=(--prerelease)
[[ "${3:-}" == "--final" ]] && flags=()
gh release create "$tag" "$zip" "$zip.sha256" "$zip.sig" -R fastermatt/thruline-bible \
  --title "Thruline ${version}" --notes-file "$notes" "${flags[@]}"
echo "Published $tag. Installed copies of Thruline will offer it within a day (or now, via Check for Updates…)."
