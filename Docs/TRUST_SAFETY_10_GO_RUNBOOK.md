# Amen Trust and Safety 10/10 Go Runbook

Last updated: 2026-05-16

This runbook is the launch gate for open social surfaces in Amen. Code can enforce many controls, but production readiness also requires operational proof, reviewer access controls, and documented decisions.

## Launch Gate

Amen is not production-wide social launch ready until all of these artifacts exist and are signed off:

- Firestore and Storage emulator tests pass for deny-by-default, report creation, media quarantine, admin-only fields, minor safety, block enforcement, deletion, and export.
- Backend function tests pass for App Check, server-side report taxonomy, case creation, evidence preservation, media quarantine, AI safety, and abuse simulation fixtures.
- Admin access requires MFA, least privilege IAM, and immutable audit logs.
- Trust and Safety reviewers are trained for child safety, sexual exploitation, legal requests, account recovery, and general abuse queues.
- Published support and safety contact information is live.
- App Store privacy labels match actual SDKs and server processors.
- Incident response and evidence preservation procedures are approved by legal and Trust and Safety leadership.

## E2EE and Private Content Decision

| Data class | Launch protection | E2EE decision |
| --- | --- | --- |
| Public posts and comments | Server-side moderation, ranking integrity, reports, blocks | Do not use E2EE |
| Public church and creator pages | Server-side moderation, verified ownership, admin audit | Do not use E2EE |
| DMs | DM requests, reportable evidence snapshots, media quarantine, adult-minor constraints | Do not enable true E2EE until user-submitted evidence export and abuse-report flow are complete |
| Private prayer requests | Strict Firestore access, retention limits, report path for shared content | App-level encryption acceptable after recovery and reporting design |
| Church note drafts | Local privacy controls, owner-only storage, export/delete | Local encryption plus server encryption |
| Journals and confession-like content | Highest privacy tier, no moderator access without user action or lawful process | Prefer local-first encryption |
| AI history | Redaction, minimization, retention limits, user delete | Do not use as model memory unless user-visible controls are enabled |
| Moderation evidence | Restricted IAM, immutable audit, retention schedule | Encrypted at rest; no client access |

## Reviewer Queues

Every severe report must create:

- `moderationCases/{caseId}` for case state and reviewer assignment.
- `trustSafetyEvents/{eventId}` for immutable audit history.
- `evidenceVault/{caseId}` for restricted evidence metadata and preservation status.
- `ncmecReadiness/{caseId}` for child-safety reports that require trained reviewer assessment.

Queue separation:

- `child_safety`
- `sexual_exploitation`
- `self_harm`
- `fraud_and_platform_abuse`
- `legal`
- `account_recovery`
- `general_abuse`

Severe actions require dual approval. Break-glass access to private material requires a reason code, audit event, and post-action review.

## NCMEC and Legal Readiness

Amen must not automatically submit CyberTipline reports from unreviewed classifier output. The required workflow is:

1. Block or hold the content/account as required by policy.
2. Preserve relevant evidence metadata in restricted storage.
3. Route the case to trained child-safety reviewers.
4. Document reviewer decision, legal basis, and any external reporting action.
5. Keep all access and export activity in immutable audit logs.

## Abuse Simulation Suite

Before wide launch, run simulations for:

- Spam burst from new accounts.
- Mass DM attempt.
- Pornographic upload.
- Grooming or online enticement pattern.
- Sextortion threat.
- Adult stranger messaging a minor.
- Minor discovery exposure.
- Blocked user retrying contact.
- Suspended user evasion.
- Fake church page and fake fundraiser.
- AI jailbreak and private note leakage.
- Malicious link in comments.

## App Store Readiness

The App Review notes must explicitly state:

- UGC filtering exists before public distribution.
- Report and block controls exist on UGC surfaces.
- Mature and unsafe content is blocked, hidden, or review-gated.
- Child-safety and sexual-exploitation reports are escalated to trained reviewers.
- Delete account is available in-app.
- Privacy labels cover Firebase, Google Sign-In, App Check, analytics, crash logging, AI processors, media moderation vendors, payment providers, and messaging/email/SMS processors.

## Release Decision

Public posts and comments can move forward only when moderation, reports, blocks, and media quarantine are proven. DMs, youth participation, groups, creator monetization, public discovery, and media-heavy sharing must remain feature-gated until the launch gate above is complete.
