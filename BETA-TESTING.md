# Install and update

When a beta is published, obtain its ZIP from this repository's GitHub Releases,
check its version/platform and supplied SHA-256, unzip, and move Thruline Bible.app into
Applications. The current target is Apple Silicon (M1 or newer), macOS 14+.
No account is needed for included study resources.

The current packager produces an ad-hoc signed, unnotarized beta. If macOS blocks
opening a trusted copy, attempt to open it once, then use System Settings → Privacy
& Security → Open Anyway. Do not disable Gatekeeper globally. A public release should
clearly state whether Developer ID signing/notarization has subsequently been added.

For optional local AI: Your AI → On this Mac → Choose a model → Download → Use model.
The three choices show download size and memory guidance. Internet is required to
download, not for subsequent local inference. Stop frees model memory; Remove deletes
the model only. Provider connections are optional and may incur their own charges.

To update, click **Update to x.y** in the toolbar when it appears (or **Thruline ›
Check for Updates…**), then **Update Now**. Thruline checks the release signature, swaps
itself and reopens. Your notes, library and model downloads live separately. Export/back up
important study work before a beta upgrade. Never accept a request to send your notes,
API keys or passwords as a condition of updating.
