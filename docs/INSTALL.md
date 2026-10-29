# Install and update

When a beta is published, obtain its ZIP from this repository's GitHub Releases,
check its version/platform and supplied SHA-256, unzip, and move Throughline.app into
Applications. The current target is Apple Silicon (M1 or newer), macOS 14+.
No account is needed for included study resources.

If upgrading from Lectern 0.19 or earlier, install Throughline.app and confirm
your notes and downloaded models appear. You can then remove the old Lectern.app;
the new app uses the same study data and model location.

The current packager produces an ad-hoc signed, unnotarized beta. If macOS blocks
opening a trusted copy, attempt to open it once, then use System Settings → Privacy
& Security → Open Anyway. Do not disable Gatekeeper globally. A public release should
clearly state whether Developer ID signing/notarization has subsequently been added.

For optional local AI: Your AI → On this Mac → Choose a model → Download → Use model.
The three choices show download size and memory guidance. Internet is required to
download, not for subsequent local inference. Stop frees model memory; Remove deletes
the model only. Provider connections are optional and may incur their own charges.

To update, quit Throughline and replace the app in Applications. Your notes, library and
model downloads live separately. Export/back up important study work before a beta
upgrade. There is no automatic updater yet. Never accept a request to send your notes,
API keys or passwords as a condition of updating.
