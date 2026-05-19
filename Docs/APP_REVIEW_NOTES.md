# Amen App Review Notes

Use this as the App Review notes source. Keep it aligned with the submitted binary and production backend.

## Machine-Checked Markers

```text
APP_REVIEW_NOTES_FINAL=false
APP_REVIEW_NOTES_OWNER=
APP_REVIEW_NOTES_REVIEW_DATE=
```

## Suggested Review Notes

Amen includes user-generated content, private community features, AI-assisted drafting/search/replies, media uploads, reporting/blocking, and account deletion.

Moderation and safety controls:

- Public UGC is subject to pre-publication and post-publication moderation.
- User media is uploaded through a quarantine/scanning path before public serving.
- Report and block flows are available for posts, comments, media, profiles, communities, messages, creator/church surfaces, and AI-generated responses where applicable.
- Serious report categories include child safety, CSAM concern, grooming/online enticement, sexual exploitation, trafficking, sextortion, non-consensual intimate imagery, threats, harassment, scams, impersonation, self-harm concern, and privacy/doxxing.
- Severe child-safety and sexual-exploitation reports create restricted Trust & Safety cases and are routed to trained reviewers. Amen does not rely on unreviewed classifier output for external child-safety reports.
- Blocking and hiding are enforced in client UI and backend access paths where applicable.
- Minor-safety controls include age-aware defaults, restricted discovery, adult-to-minor messaging constraints, and heightened moderation for youth/community surfaces.

AI safety controls:

- Berean AI and related AI surfaces use prompt-injection defenses, input redaction, output moderation, tool-permission boundaries, and refusal handling for exploitation, harassment, scams, malware, sexual content involving minors, self-harm escalation, and unsafe spiritual authority.
- AI-generated Bible references require verification/citation safeguards.
- Users can clear AI history where retained, and AI memory/personalization must be user-visible and controllable.

Privacy and account controls:

- Delete account is available in-app.
- Private notes, prayer data, AI history, and user content follow documented deletion/retention behavior.
- Legal/moderation evidence may be preserved only where required by policy and law.
- Published safety/support contact information is available at the URL listed in the release record.

Reviewer access:

- If App Review needs a demo account, provide a non-production test account with representative content and no real private user data.

## Required Final Checks

- [ ] Notes match the exact features enabled in the submitted build.
- [ ] Demo credentials, if provided, do not expose real user content.
- [ ] Delete-account path has been tested in the submitted build.
- [ ] Report/block controls are visible on every enabled UGC surface.
- [ ] App Review notes mention any gated social, youth, AI, creator, payment, or media features.
