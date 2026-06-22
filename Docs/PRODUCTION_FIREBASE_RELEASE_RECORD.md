# Amen Production Firebase Release Record

This record proves the production backend is deployed to the intended Firebase project with App Check and production moderation settings.

## Machine-Checked Markers

```text
FIREBASE_PRODUCTION_PROJECT_ID=
FIREBASE_DEPLOYED_PROJECT_ID=
FIREBASE_RULES_DEPLOYED=false
FIREBASE_FUNCTIONS_DEPLOYED=false
FIREBASE_STORAGE_RULES_DEPLOYED=false
FIREBASE_DATABASE_RULES_DEPLOYED=false
FIREBASE_HOSTING_DEPLOYED=false
APP_CHECK_PRODUCTION_ENFORCED=false
PRODUCTION_MODERATION_PROVIDERS_CONFIGURED=false
PRODUCTION_FIREBASE_RELEASE_OWNER=
PRODUCTION_FIREBASE_RELEASE_DATE=
```

## Required Deployment Evidence

- [ ] Firestore rules deployed from `AMENAPP/firestore.deploy.rules`.
- [ ] Storage rules deployed from `AMENAPP/storage.rules`.
- [ ] Realtime Database rules deployed from `AMENAPP/database.rules.json`.
- [ ] Backend functions deployed from the intended production codebase.
- [ ] Firebase Hosting deployed with the public safety and privacy pages from `public/`.
- [ ] App Check enforcement is enabled for callable/backend entry points and supported Firebase products.
- [ ] Production moderation providers are configured with real restricted credentials, not placeholders.
- [ ] Production project id matches the App Store build configuration.

## Required Final Checks

- [ ] `scripts/verify_trust_safety_10_go.sh` passes with `REQUIRE_PRODUCTION_SECRETS=1`.
- [ ] Firebase console confirms App Check enforcement.
- [ ] Firebase console confirms functions deployed after the latest git revision.
- [ ] Firebase console confirms Firestore/Storage/Database rules deployment timestamps.
- [ ] Firebase Hosting serves `/safety` over HTTPS and the same URL is recorded in `Docs/PUBLISHED_SAFETY_CONTACT_RECORD.md`.
