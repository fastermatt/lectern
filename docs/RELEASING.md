# Prepare a release

## Repository setup and future forks

The official repository is https://github.com/fastermatt/lectern. Initial publication
is complete; do not re-create it. The commands below document setup for future forks.

Review the exported tree, MIT scope, THIRD_PARTY_NOTICES, PUBLIC-SOURCE and governance
workflow. Do not upload the original private development folder. Run the public snapshot
validator, tests and a redacted secret scan. Review Git's staged file list and commit
history. The source export has its own history with no imported private history.

Create an empty GitHub repository under the intended user/organization, then push this
repository's main branch. For example, after confirming owner and visibility:

```sh
gh repo create OWNER/REPOSITORY --public --source . --remote origin --push
```

This command publishes source; run it only when intentionally creating a new repository. Alternatively add the remote from GitHub's instructions and push normally.
Use the Git CLI rather than GitHub's browser uploader for this resource-rich repository.

Enable Issues, Discussions if useful, private vulnerability reporting, secret scanning
and push protection where available. Configure branch rules requiring PR review and the
`portable` and `macos` checks after their first successful hosted run. Disable force-push
and deletion of main, require resolved discussions, and keep workflow tokens read-only.
Do not expose release credentials to fork PRs. CI uses pull_request, never pull_request_target.

Recruit a backup technical maintainer and editorial reviewers. Assign CODEOWNERS only
to real users/teams that have accepted responsibility; no fictitious reviewers are
preconfigured. Agree on the governance workflow before presenting it as a staffed service.

## Build a beta

1. Update Info.plist version/build, release notes and resource provenance as needed.
2. Run `python3 scripts/verify-public-source.py`, Python validators and `swift test`.
3. Rebuild Scripture/patristic resources when those inputs change. Review, then update
   snapshot hashes; a matching hash is not an editorial or legal approval.
4. Run `python3 scripts/bootstrap-local-ai.py` and `scripts/package-app.sh` on Apple Silicon.
5. Inspect light/dark, packaged CLI and optional local-model behavior. Run on a clean
   second Mac. Code changes do not justify claiming theological review of a resource.
6. Verify `codesign --verify --deep --strict /path/to/Lectern.app` and archive integrity.
7. Generate SHA-256 checksums. Create a draft GitHub Release with version tag, ZIP,
   checksum and readable notes. Keep code history separate from release archives/models.
8. State signing/notarization status and known limits; publish only after review.

The current script signs ad hoc. Developer ID signing/notarization and a secure updater
remain separate work; do not describe this beta as Apple-approved or automatically updated.
Models are user downloads, not Git LFS assets. Never include publisher keys or caches.
