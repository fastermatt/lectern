# Install and update

## Easiest: one line in Terminal (no security prompts)

Open Terminal (Applications → Utilities) and paste:

```
curl -fsSL https://raw.githubusercontent.com/fastermatt/thruline-bible/main/scripts/install-thruline.sh | bash
```

It downloads the newest release from this repository, checks it against the release's
published SHA-256 and the app's code signature, and places Thruline in
Applications, replacing an older copy. Run the same line to update (0.22 and later can also update themselves in one click). Your notes,
library and AI models live outside the app and are not touched. Because Terminal
downloads are not marked as coming from the internet, macOS does not show the
"unidentified developer" prompts — Gatekeeper is not disabled; the script's checks
are what you are trusting. Read the script first if you prefer:
[scripts/install-thruline.sh](../scripts/install-thruline.sh).

## From the browser

When a beta is published, obtain its ZIP from this repository's GitHub Releases,
check its version/platform and supplied SHA-256, unzip, and move Thruline Bible.app into
Applications. The current target is Apple Silicon (M1 or newer), macOS 14+.
No account is needed for included study resources.

If upgrading from Lectern 0.19 or earlier, install Thruline Bible.app and confirm
your notes and downloaded models appear. You can then remove the old Lectern.app;
the new app uses the same study data and model location.

The current packager produces an ad-hoc signed, unnotarized beta. If macOS blocks
opening a browser-downloaded copy, attempt to open it once, then use System Settings →
Privacy & Security → Open Anyway (one time only). Do not disable Gatekeeper globally.
The maintainer can remove these warnings for everyone by signing with an Apple
Developer ID and notarizing (`scripts/notarize-release.sh`, ready but not yet run). A public release should
clearly state whether Developer ID signing/notarization has subsequently been added.

For optional local AI: Your AI → On this Mac → Choose a model → Download → Use model.
The three choices show download size and memory guidance. Internet is required to
download, not for subsequent local inference. Stop frees model memory; Remove deletes
the model only. Provider connections are optional and may incur their own charges.

From 0.22 on, Thruline updates itself: when a newer release is published an **Update to
x.y** button appears in the toolbar (or choose **Thruline › Check for Updates…**). Click
**Update Now**; it downloads, checks the release signature, swaps the app and reopens.
Settings › About › Updates turns automatic checks and beta releases on or off. Copies older
than 0.22 need one manual update (the Terminal line above). Your notes, library and model
downloads live separately and are not touched. Export/back up important study work before a
beta upgrade. Never accept a request to send your notes,
API keys or passwords as a condition of updating.
