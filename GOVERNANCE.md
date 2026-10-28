# Review and maintenance

This initial repository provides a contribution workflow, not an appointed council or
an adopted new doctrinal constitution. It preserves the existing content rules in
AGENTS.md. The broader constitutional proposals and research drafts are not published
as binding policy. Any future change to those rules needs an explicit, public decision.

## Roles we need

- Technical maintainers: review code, compatibility, accessibility, tests and releases.
- Resource reviewers: verify editions, transcription, rights and attribution.
- Editorial reviewers: assess specific historical/theological claims and contrary
  evidence, with their reasoning and sources recorded.
- Community maintainers: triage reports, help newcomers, and enforce respectful conduct.

One person can help in more than one area, but code access does not confer theological
or rights expertise. No additional maintainers or review board are appointed by this
file. Recruit at least two independent maintainers and qualified resource reviewers;
record who has accepted each role before depending on that coverage. The founder is
not a mandatory reviewer or permanent appeal backstop. Lack of reviewers means pending,
not automatic approval or an assignment to the founder.

## Changes and decisions

Routine code changes need a focused PR, relevant tests and review by another maintainer
when available. Until a second maintainer exists, any self-merged technical change
must disclose that exception; never present it as independent review. Content/rights
claims cannot use that exception to declare themselves independently reviewed.

For new doctrinal cautions or changes to content policy, keep the claim narrow: exact
edition/passage, primary evidence, historical reception, uncertainty and meaningful
contrary readings. Seek two independent human reviews, including relevant subject
expertise. A contributor cannot approve their own proposal; an AI does not count.
When reviewers disagree, record why and keep the claim pending or explicitly disputed.
No majority of drive-by comments or commit access silently changes the content standard.

Existing human-curated Westminster links still require named reviewers and dates.
No tool may auto-promote a candidate or auto-classify a book based on author identity.
Technical validators check shape and provenance, not orthodoxy.

## Appeals and continuity

Appeal with a linked decision, the disputed claim and new or overlooked evidence.
Request a reviewer who did not make the original decision. If none is available,
leave the appeal open with that fact recorded. Do not promise a ruling or response time.
Publish decisions in issues/PRs so time zones and private meetings do not control access.

Before public launch, configure protected branches, explicit review ownership, private
security reporting and at least one backup maintainer. Permissions should be scoped to
real duties. Maintainers can step back without being expected to keep the project alive
alone. Releases must document coverage gaps and review exceptions. See docs/RELEASING.md.
