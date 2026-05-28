# AMEN Premium Backend Deployment

This repo now contains the app-side product IDs, local StoreKit test config, Firebase callables, and Firestore rule hardening for AMEN Plus / Pro.

## Product IDs

Create these in App Store Connect using the same identifiers:

- `com.amen.plus.monthly` - auto-renewable subscription
- `com.amen.plus.yearly` - auto-renewable subscription
- `com.amen.pro.monthly` - auto-renewable subscription
- `com.amen.pro.yearly` - auto-renewable subscription
- `com.amen.pro.lifetime` - non-consumable

The local Xcode test products are in `AmenStoreKit.storekit`. The shared `AMENAPP` run scheme is configured to use that StoreKit file.

## Firebase Functions

Premium functions live in `functions/premiumEntitlements.js` and are exported from `functions/index.js`:

- `getPremiumEntitlement`
- `syncPremiumEntitlement`
- `appStoreServerNotificationV2`
- `listCustomTopicTags`
- `createCustomTopicTag`
- `recordAIUsageAndCheckLimit`
- `requirePremiumFeature`

## App Store Server API Environment

Set these environment variables or Secret Manager-backed values before production deploy:

- `APP_STORE_BUNDLE_ID`
- `APP_STORE_APP_APPLE_ID`
- `APP_STORE_ISSUER_ID`
- `APP_STORE_KEY_ID`
- `APP_STORE_PRIVATE_KEY`
- `APP_STORE_ENVIRONMENT` (`Sandbox` or `Production`)

The current backend validates decoded transaction payload shape, product ID, bundle ID, expiration, and environment. For full cryptographic server verification, wire these credentials into Apple's App Store Server Library verifier and reject transactions that fail signature validation.

## Deploy

If Firebase CLI and Node are installed and authenticated:

```bash
bash scripts/deploy-premium-backend.sh
```

Manual equivalent:

```bash
node scripts/strip-rules.js
firebase deploy --only functions:default:getPremiumEntitlement,functions:default:syncPremiumEntitlement,functions:default:appStoreServerNotificationV2,functions:default:listCustomTopicTags,functions:default:createCustomTopicTag,functions:default:recordAIUsageAndCheckLimit,functions:default:requirePremiumFeature,firestore:rules
```

## App Store Server Notifications

After deploy, register the HTTPS endpoint for:

```text
appStoreServerNotificationV2
```

Use the deployed Firebase URL for the `amen-5e359` project and `us-central1` region. Register sandbox first, then production when the products are live.

## Firestore Rules

The deploy source of truth is:

```text
AMENAPP/firestore 18.rules
```

`scripts/strip-rules.js` generates:

```text
AMENAPP/firestore.deploy.rules
```

Premium-sensitive user fields and usage/tag counters are server-owned. Clients can read their custom topic tags and usage records, but cannot write those collections directly.
