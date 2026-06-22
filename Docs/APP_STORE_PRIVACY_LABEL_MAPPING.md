# Amen App Store Privacy Label Mapping

This document must match the actual App Store Connect privacy nutrition label before submission.

## Machine-Checked Markers

Set these only after the release owner and legal/privacy owner review the live App Store Connect answers against the production build, Firebase project, SDK list, and backend processors.

```text
APP_STORE_PRIVACY_LABELS_REVIEWED=false
APP_STORE_PRIVACY_LABELS_OWNER=
APP_STORE_PRIVACY_LABELS_REVIEW_DATE=
```

## Data Categories To Review

| App Store category | Amen collection/use | Linked to user | Tracking | Notes |
| --- | --- | --- | --- | --- |
| Contact Info | Email, name/display name, support contact, account recovery | Yes | No unless separately enabled | Firebase Auth, Google Sign-In, support workflows |
| User Content | Posts, comments, prayer requests, DMs, church notes, media, reports | Yes | No | Includes UGC moderation and evidence preservation where required |
| Identifiers | Firebase UID, device/app instance identifiers, App Check signals | Yes | No | Used for auth, abuse prevention, diagnostics |
| Usage Data | Feature usage, AI usage counts, moderation actions, safety events | Yes | No unless ad tracking is enabled | Analytics must match actual SDK configuration |
| Diagnostics | Crash logs, performance/error logs | May be linked | No | Confirm crash/diagnostics provider settings |
| Purchases | Subscriptions, donations, creator/community payments | Yes | No | Stripe/App Store purchase paths must match active product setup |
| Location | Church discovery or nearby features if enabled | Yes if collected | No | Must be disabled or disclosed if collected |
| Contacts | Invite/contact import only if enabled | Yes if collected | No | Do not disclose as collected unless feature ships |
| Search History | Search and AI query history if retained | Yes | No | Must match retention and delete controls |
| Sensitive Info | Private prayers, notes, child-safety reports, legal/safety evidence | Yes | No | Retention and access controls must match policy |

## Third-Party Processors To Confirm

- Firebase Auth, Firestore, Storage, Functions, App Check, Analytics/Crashlytics if enabled.
- Google Sign-In.
- AI providers used by Berean AI and AI review surfaces.
- Media/text moderation providers, including CSAM hash lookup provider and Perspective or approved equivalent.
- Stripe or other payment providers when Covenant payments are enabled.
- Email/SMS/support providers if used for notifications or account recovery.

## Required Final Checks

- [ ] Labels include all data collected by app code, SDKs, backend functions, and third-party processors.
- [ ] Labels distinguish data linked to user vs not linked.
- [ ] Labels do not claim tracking unless ATT-tracked cross-app/company use exists.
- [ ] Delete-account behavior and retained legal/moderation evidence are reflected in privacy policy.
- [ ] AI history, private notes, prayers, DMs, and media retention are accurately described.
