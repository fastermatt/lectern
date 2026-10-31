#!/bin/zsh
# Sign a packaged Thruline release with a Developer ID and notarize it with Apple, so
# downloads open with no "unidentified developer" warning at all.
#
# Requires (one-time, by the maintainer):
#   1. Apple Developer Program membership and a "Developer ID Application" certificate in the login keychain.
#   2. A stored notary profile:  xcrun notarytool store-credentials thruline-notary --apple-id … --team-id …
#
# Usage:  DEVELOPER_ID="Developer ID Application: Name (TEAMID)" scripts/notarize-release.sh Releases/Thruline-Bible-0.22.0.zip
# Writes  Releases/Thruline-Bible-<version>-notarized.zip and its .sha256. The input ZIP is left unchanged.
# Not yet exercised end to end: no Developer ID was available when this was written (2026-10-31).
set -euo pipefail
zip="${1:?Pass the packaged release ZIP}"
identity="${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
profile="${NOTARY_PROFILE:-thruline-notary}"
work=$(mktemp -d /private/tmp/thruline-notarize.XXXXXX)
trap 'rm -rf "$work"' EXIT

ditto -x -k "$zip" "$work"
app="$work/Thruline Bible.app"
[[ -d "$app" ]] || { echo "error: no Thruline Bible.app in $zip" >&2; exit 1; }
entitlements="$work/entitlements.plist"
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <!-- No exceptions: the local-AI helper's libraries are signed with the same team ID above. -->
</dict></plist>
PLIST

# Inside-out: helpers and libraries first, then the app, each with the hardened runtime and a secure timestamp.
find "$app/Contents" \( -name '*.dylib' -o -perm -111 -type f \) ! -path '*/MacOS/StudyTable' -print0 |
  while IFS= read -r -d '' item; do
    if file -b "$item" | grep -q 'Mach-O'; then
      codesign --force --timestamp --options runtime --sign "$identity" "$item"
    fi
  done
codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

submit="$work/submit.zip"
ditto -c -k --keepParent "$app" "$submit"
xcrun notarytool submit "$submit" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"

out="${zip%.zip}-notarized.zip"
ditto -c -k --keepParent "$app" "$out"
shasum -a 256 "$out" | tee "$out.sha256"
echo "Notarized release: $out"
