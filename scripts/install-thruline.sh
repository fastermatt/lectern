#!/bin/bash
# Install or update Thruline Bible from its GitHub release in one step:
#
#   curl -fsSL https://raw.githubusercontent.com/fastermatt/thruline-bible/main/scripts/install-thruline.sh | bash
#
# Why this avoids the "unidentified developer" prompts: macOS attaches a quarantine flag
# to files downloaded by browsers, and Gatekeeper prompts for unnotarized apps that carry it.
# Files fetched by curl in Terminal are not quarantined. Trust therefore rests on this
# script's checks instead: an HTTPS download from this repository's GitHub release, the
# release's published SHA-256, and a strict code-signature check of the app bundle.
# Gatekeeper itself is never disabled. Your notes, library and AI models live outside the
# app and are not touched.
set -euo pipefail

repo="fastermatt/thruline-bible"
tag="${THRULINE_TAG:-}"
dest="${THRULINE_DEST:-/Applications/Thruline Bible.app}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf 'Thruline Bible install stopped: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "this installer is for macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "this beta needs an Apple Silicon Mac (M1 or newer)."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "macOS 14 Sonoma or newer is required."

work=$(mktemp -d /tmp/thruline-install.XXXXXX)
trap 'rm -rf "$work"' EXIT

say "Finding the newest Thruline release…"
if [[ -n "$tag" ]]; then api="https://api.github.com/repos/$repo/releases/tags/$tag"
else api="https://api.github.com/repos/$repo/releases?per_page=1"; fi
curl -fsSL --proto '=https' --tlsv1.2 "$api" -o "$work/release.json" || fail "could not reach GitHub."
/usr/bin/python3 - "$work/release.json" > "$work/assets.txt" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
release = data[0] if isinstance(data, list) else data
assets = release.get("assets", [])
zip_url = next((a["browser_download_url"] for a in assets if a["name"].endswith(".zip")), "")
sum_url = next((a["browser_download_url"] for a in assets if a["name"].endswith((".sha256", ".sha256.txt"))), "")
print(zip_url or "-", sum_url or "-", release.get("tag_name", "?"))
PY
read -r zip_url sum_url version < "$work/assets.txt"
[[ "$zip_url" == https://github.com/$repo/releases/download/* ]] || fail "the release has no app download."
[[ "$sum_url" == https://github.com/$repo/releases/download/* ]] || fail "the release has no published checksum, so it cannot be verified."

say "Downloading Thruline ${version}…"
curl -fL --proto '=https' --tlsv1.2 --progress-bar "$zip_url" -o "$work/Thruline.zip"
curl -fsSL --proto '=https' --tlsv1.2 "$sum_url" -o "$work/checksum.txt"
expected=$(grep -Eo '[0-9a-f]{64}' "$work/checksum.txt" | head -1)
actual=$(shasum -a 256 "$work/Thruline.zip" | cut -d' ' -f1)
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "the download does not match its published SHA-256. Nothing was installed."
say "Checksum verified."

ditto -x -k "$work/Thruline.zip" "$work/unpacked"
app=$(find "$work/unpacked" -maxdepth 2 -name '*.app' -type d | head -1)
[[ -n "$app" ]] || fail "the download did not contain the app."
codesign --verify --deep --strict "$app" || fail "the app's code signature did not verify. Nothing was installed."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "com.fastermatt.studytable.beta" ]] \
    || fail "unexpected app identity. Nothing was installed."

if [[ -z "${THRULINE_DEST:-}" ]] && pgrep -xq StudyTable; then
    say "Quitting the running Thruline so it can be updated…"
    osascript -e 'tell application id "com.fastermatt.studytable.beta" to quit' >/dev/null 2>&1 || true
    sleep 2
fi
if [[ -d "$dest" ]]; then
    backup="$work/previous-Thruline Bible.app"
    mv "$dest" "$backup" 2>/dev/null || sudo mv "$dest" "$backup"
fi
if ! ditto "$app" "$dest" 2>/dev/null; then sudo ditto "$app" "$dest"; fi
# The app was called Throughline before 0.22; remove that copy once the renamed one is in place.
legacy="/Applications/Throughline.app"
if [[ -z "${THRULINE_DEST:-}" && -d "$legacy" && "$legacy" != "$dest" ]]; then
    rm -rf "$legacy" 2>/dev/null || sudo rm -rf "$legacy"
    say "Removed the old Throughline.app (now called Thruline Bible). Your notes are unchanged."
fi
say "Thruline Bible ${version} is installed in Applications."
[[ -n "${THRULINE_NO_OPEN:-}" ]] || open "$dest"
