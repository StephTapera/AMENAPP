# Amen App Review Notes

Use this as the App Review notes source. Keep it aligned with the submitted binary and production backend.

## Machine-Checked Markers

```text
APP_REVIEW_NOTES_FINAL=true
APP_REVIEW_NOTES_OWNER=steph tapera
APP_REVIEW_NOTES_REVIEW_DATE=2026-06-17
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

AI Disclosure:

- Berean AI is disclosed as an AI-powered assistant in onboarding, in the chat greeting screen ("I'm Berean, an AI assistant"), and via an AI disclosure prefix prepended to every Berean response.
- Berean is not a pastor, prophet, therapist, or emergency responder. Users are directed to human professionals and emergency services where appropriate. Crisis responses include 988 Suicide & Crisis Lifeline and are non-dismissible.

Gated / feature-flagged surfaces (currently OFF by default):

- Giving / donations: disabled pending payment compliance review.
- CSAM media scanning: fail-closed; no media upload is processed until PhotoDNA/NCMEC integration is complete.
- Guardian consent for 13-17: guarded pending legal design review.
- Live streaming (CreatorPro tier): gated OFF.

Reviewer access:

- Demo account: reviewer@amenapp-demo.com / AmenReview2026!
  - The account has seeded posts, a Berean AI conversation, a church note, and a followed user.
  - No real user data. Account is in a sandbox Firebase project with moderated test content.
  - You can report content via the three-dot menu on any post, block a user from their profile, and delete the account from Settings → Account → Delete Account.
- AI features work immediately in the demo account with no additional setup.
- Subscription/donation flows are not active in this build (givingEnabled=false).

## Required Final Checks

- [x] Notes match the exact features enabled in the submitted build.
- [x] Demo credentials provided with seeded content, no real user data.
- [x] Delete-account path tested in submitted build (Settings → Account → Delete Account).
- [x] Report/block controls visible on posts, comments, profiles, messages, and AI responses.
- [x] AI disclosure visible in Berean onboarding and chat greeting.
- [x] Gated features (giving, CSAM scanning, guardian consent) explicitly documented above.
