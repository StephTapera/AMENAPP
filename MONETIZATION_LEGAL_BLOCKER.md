# Monetization Legal Blocker

**Generated:** 2026-06-27  
**Status:** PRODUCT/LEGAL BLOCKED / NO-GO

## StoreKit Restore Status

StoreKit restore coverage is wired in commit:

```text
f8718ef9 Add restore purchase coverage to StoreKit paywalls
```

Covered StoreKit-backed surfaces:

| Surface | Evidence |
|---|---|
| Account tier paywall | `AMENAPP/AMENAPP/Monetization/AmenAccountPaywallView.swift` calls `AmenPlatformStoreKitService.restorePurchases()` |
| Platform StoreKit service | `AMENAPP/AMENAPP/Monetization/AmenPlatformStoreKitService.swift` syncs StoreKit and refreshes account entitlements |
| 242 hub paywall | `AMENAPP/TwoFourTwoSubscriptionView.swift` restores only verified active `Transaction.currentEntitlements` |
| Space membership paywall | `AMENAPP/AMENAPP/ConnectSpaces/Monetization/AmenSpacePaywallView.swift` calls `AmenStoreKitService.restorePurchases()` |

## Stripe / Covenant Status

Current evidence:

- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantCheckoutService.swift` describes a Stripe-hosted checkout flow for Covenant tier subscriptions.
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AppStorePaymentReadinessPolicy.swift` disables hosted digital checkout in release builds unless `ALLOW_HOSTED_DIGITAL_CHECKOUT` is explicitly configured after App Store policy review.
- `AMENAPP/AMENAPP/CommunityOS/Monetization/AmenEntitlementService.swift` also guards hosted checkout behind `AppStorePaymentReadinessPolicy.allowsHostedDigitalCheckout`.

## Risk

If Covenant or CommunityOS hosted checkout sells digital content/features inside the iOS app, App Store Guideline 3.1.1 requires StoreKit unless Product/Legal has a written approved exemption.

## Required Product / Legal Decision

Choose exactly one:

1. Migrate Covenant/CommunityOS digital subscriptions to StoreKit.
2. Keep Stripe only for physical goods/services, donations, enterprise/org billing, or another legally approved external use.
3. Provide written legal/product exemption evidence before release.

## Release Impact

This blocker remains open until a decision is made and verified. Do not mark monetization/App Store readiness green from StoreKit restore coverage alone.
