# Amen Production Trust and Safety Signoff

This document must be completed before enabling production-wide social launch for DMs, minors, groups, creator monetization, public discovery, or media-heavy sharing.

## Required Technical Evidence

- [ ] Backend tests pass: `cd Backend/functions && npm test -- --runInBand`
- [ ] Backend typecheck passes: `cd Backend/functions && npm run typecheck`
- [ ] Rules launch gates pass: `cd Backend/rules-tests && npm run test:launch-gates`
- [ ] Xcode build passes from the active scheme.
- [ ] No Swift direct writes to `reports` or `userReports`.
- [ ] Production media moderation providers configured:
  - [ ] `REQUIRE_MEDIA_MODERATION_PROVIDERS=true`
  - [ ] `CSAM_HASH_LOOKUP_URL`
  - [ ] `CSAM_HASH_LOOKUP_TOKEN`
  - [ ] `PERSPECTIVE_API_KEY` or approved equivalent text safety provider

## Required Operations Signoff

- [ ] Trust and Safety reviewer training completed.
- [ ] Child safety escalation workflow approved.
- [ ] Sexual exploitation escalation workflow approved.
- [ ] NCMEC readiness workflow approved by legal.
- [ ] Evidence preservation and retention schedule approved.
- [ ] Break-glass access policy approved.
- [ ] Admin MFA and least-privilege access verified.
- [ ] Published safety/contact page is live.
- [ ] App Store review notes and privacy labels reviewed.
- [ ] Incident response owner and backup owner assigned.

## Signatures

| Role | Name | Date | Approval |
| --- | --- | --- | --- |
| Engineering owner |  |  |  |
| Trust and Safety owner |  |  |  |
| Legal/privacy owner |  |  |  |
| App Store release owner |  |  |  |

## Machine-Checked Approval Markers

These markers are intentionally set to `false` until the named human owners complete review. The production verifier requires all four approvals and `APPROVAL_STATUS=GO` when run with `REQUIRE_PRODUCTION_SECRETS=1`.

```text
APPROVAL_STATUS=NO-GO
ENGINEERING_APPROVED=false
TRUST_SAFETY_APPROVED=false
LEGAL_PRIVACY_APPROVED=false
APP_STORE_RELEASE_APPROVED=false
```

## Launch Decision

- [ ] GO
- [ ] NO-GO

Decision notes:

Final verifier:

```bash
scripts/verify_app_store_release_ready.sh
```

This must pass before App Store submission. Do not change the machine-checked markers to `GO`/`true` until real owners have approved the release evidence.
