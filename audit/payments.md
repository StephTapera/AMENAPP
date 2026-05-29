# Payments / Stripe / Giving Audit

**Date:** 2026-05-28  
**Auditor:** Claude Code  
**Scope:** Full payment and giving system — iOS client, Cloud Functions, Stripe integration, IAP compliance

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `GivingInAppSheet.swift:397–405` | **Blocker** | Payment intent — not wired | Apple Pay `didAuthorizePayment` callback calls `completion(.success)` and shows success UI **before sending the token anywhere**. The `TODO: Send payment.token.paymentData to your Stripe backend` comment confirms this. Real money is **never moved**. |
| `GivingInAppSheet.swift:271–279` | **Blocker** | Card fallback — stub | The "Donate with Card" fallback button (shown when Apple Pay is unavailable) calls `withAnimation { showSuccess = true }` with zero Stripe SDK call. Any user without Apple Pay sees a fake success. |
| `StudioPaymentService.swift` (all) | **Blocker** | Cloud Functions missing | `stripeCreateConnectedAccount`, `stripeGetAccountStatus`, `stripeCreatePaymentIntent`, and `stripeRequestPayout` are called from Swift but **none exist in `Backend/functions/src/`**. Every Studio payment call will throw a Firebase Functions `not-found` error. |
| `SpacesEntitlementService.swift:116` | **Blocker** | Cloud Function missing | `createSpaceCheckoutSession` is called for paid Space purchases but does not exist in the deployed index. Purchase flow is dead. |
| `AmenCovenantCheckoutService.swift:79` | **Blocker** | Cloud Function missing | `createCovenantCheckoutSession` is called for Covenant tier subscriptions but does not exist in `Backend/functions/src/index.ts` exports. Covenant paid tiers are broken. |
| `SpacesPurchaseService.swift:124` | **Blocker** | Cloud Function missing | `purchaseSpaceAccess` is referenced in `SpacesCallable` enum and called by `SpacesPurchaseService`, but not in the deployed Cloud Functions index. |
| `CommunityStripeOnboardingView.swift:372` | **Blocker** | Cloud Function missing | `createStripeConnectAccount` is called for community Stripe onboarding but not exported from any functions index. Community owners cannot enable paid Spaces. |
| `GivingInAppSheet.swift:363` | **Blocker** | Merchant ID mismatch | Apple Pay uses `merchantIdentifier = "merchant.com.amen.giving"` but the entitlement file (`AMENAPP.entitlements:17`) only registers `merchant.com.amen.app`. Apple Pay will always fail at runtime until entitlement is updated or merchant IDs are unified. |
| `Backend/functions/src/` (entire dir) | **Blocker** | No Stripe webhook handler | There is no `onRequest` Cloud Function that receives and verifies Stripe webhook events. `AmenSubscriptionService.swift` comments say "A Stripe webhook... writes entitlements" but the implementation does not exist. Without this, payment confirmations never write to Firestore. |
| `Backend/functions/src/` (entire dir) | **Blocker** | No Stripe secret config | No `defineSecret("STRIPE_SECRET_KEY")` or `STRIPE_WEBHOOK_SECRET` configuration found anywhere in Cloud Functions source. The `stripe` npm package is mocked in `__mocks__/stripe.js` (test only) but never imported in any production function. |
| `GivingInAppSheet.swift:12–13` | **High** | Setup instructions incomplete | File header says "Replace Stripe publishable key placeholder in StripeGivingBridge" — but `StripeGivingBridge` does not exist anywhere in the project. This placeholder class was never created. |
| `Config.xcconfig` | **High** | No STRIPE_PUBLISHABLE_KEY entry | `StudioPaymentService.swift:9` says "Set STRIPE_PUBLISHABLE_KEY in Config.xcconfig", but `Config.xcconfig` has no such key. The Stripe iOS SDK is not imported or initialized anywhere in the app. |
| `StudioPaymentService.swift:93–117` | **High** | Client secret handling — no SDK use | `createPaymentIntent` returns a `clientSecret` but there is no Stripe iOS SDK (`STPPaymentSheet` or `StripePaymentSheet`) to present a payment UI with it. The secret is returned but never used to collect card details. |
| `SpacesPurchaseService.swift:64–65` | **High** | `pendingClientSecret` is orphaned | Service publishes `pendingClientSecret` for the Stripe payment sheet but no view ever observes it and presents a payment UI. The payment sheet step is architecturally missing. |
| `GivingInAppSheet.swift:292–299` | **High** | Apple Pay recurring not supported | `PKPaymentSummaryItem.label` is mutated for recurring mode but `PKPaymentRequest` does not use `PKRecurringPaymentRequest` (iOS 16+) or a `PKPaymentTokenContext`. Recurring billing setup is non-functional. |
| `StudioPaymentService.swift:122–133` | **High** | No failure state after payout | `requestPayout` calls a missing CF; when it throws, `isLoading` is reset via `defer` but no error is surfaced to the caller or stored in a published property. The UI has no way to show a payout error. |
| `AmenSubscriptionService.swift:66–67` | **High** | RevenueCat webhook assumed but absent | Comments claim a RevenueCat webhook writes to `users/{uid}/entitlements/active`. There is no RevenueCat Cloud Function in the index and `StudioSubscriptionService.swift` only conditionally imports RevenueCat behind `#if canImport(RevenueCat)`. Entitlement source of truth is unresolved. |
| `SpacesEntitlementService.swift:87–89` | **Med** | Entitlement collection naming inconsistency | `SpacesEntitlementService` reads from `entitlements/{uid}_{spaceId}` but `SpacesPurchaseService` header comment says the webhook writes to `entitlements` (flat collection). No server writes this collection. The listener will never fire. |
| `GivingInAppSheet.swift:56` | **Med** | Platform fee hardcoded in two places | 2% fee is hardcoded in both `GivingInAppSheet.swift:56` and `SpacesFeeCalculator.swift:21`. A comment says they "MUST match" but there is no shared constant, runtime enforcement, or server-side validation. Fee can drift. |
| `GivingInAppSheet.swift:289` | **Med** | Receipt disclosure is false | UI tells users "You'll receive a tax receipt at your verified email address" but there is no email receipt mechanism in the nonprofit giving flow (no Cloud Function, no Firestore write to `receipts/`). The Giving OS `GivingReceipt` model exists but no callable creates receipts for nonprofit donations. |
| `GivingOrgDetailView.swift:450–503` | **Med** | GiveConfirmationSheet does an external URL redirect, not in-app giving | For nonprofit org giving, tapping "Give" opens `org.donationUrl` in Safari. No in-app payment happens. `GivingInAppSheet` (which attempts Apple Pay) is a separate flow that is not connected to `GivingOrgDetailView`. The two giving paths are siloed and inconsistent. |
| `CommunityStripeOnboardingView.swift:405–406` | **Med** | `prefersEphemeralWebBrowserSession = false` for Stripe onboarding | Stripe onboarding session shares browser cookies, meaning a logged-in Stripe dashboard session could pre-fill or interfere with onboarding. For financial identity verification, `prefersEphemeralWebBrowserSession = true` is safer. |
| `AmenCovenantCheckoutService.swift:153–165` | **Med** | Callback URL host validation is too lenient | Handles any URL with `scheme == "amen"` and `host == "covenant-checkout"`. Deep-link scheme `amen://` should have a more specific registered callback URL and the URL query params should be validated more carefully (e.g. `membershipId` is accepted without format/length check). |
| `StudioPaymentService.swift:66–87` | **Low** | Account status polling — no retry strategy | `refreshAccountStatus` silently swallows errors. If the missing CF were deployed, a transient error would leave `hasConnectedAccount = false` forever in a session. No retry or exponential backoff. |
| `SpacesFeeCalculator.swift:37–38` | **Low** | Stripe fee estimate may be wrong at runtime | `stripeFeeRate = 0.029` and `stripeFixedFee = 30` are hardcoded client-side. Stripe's actual rate for international cards, ACH, or BNPL varies. The "~" tilde prefix on the payout label is the only disclosure. |
| `AmenSubscriptionService.swift:87–101` | **Low** | Entitlement listener missing error recovery | The Firestore snapshot listener silently logs errors but does not retry or surface degraded state to users. If the listener fails, users appear as free tier indefinitely. |

---

## Not Fully Wired

### 1. Stripe integration is almost entirely absent server-side

None of the following Cloud Functions referenced by Swift client code exist in `Backend/functions/src/index.ts`:

| CF Name | Called From | Purpose |
|---------|-------------|---------|
| `stripeCreateConnectedAccount` | `StudioPaymentService.swift:51` | Creator Studio Stripe Connect onboarding |
| `stripeGetAccountStatus` | `StudioPaymentService.swift:71` | Creator Studio account status check |
| `stripeCreatePaymentIntent` | `StudioPaymentService.swift:103` | Studio purchase payment intent |
| `stripeRequestPayout` | `StudioPaymentService.swift:128` | Creator payout trigger |
| `createCovenantCheckoutSession` | `AmenCovenantCheckoutService.swift:79` | Covenant tier subscriptions |
| `createStripeConnectAccount` | `CommunityStripeOnboardingView.swift:372` | Community paid Spaces onboarding |
| `createSpaceCheckoutSession` | `SpacesEntitlementService.swift:116` | Spaces checkout (Stripe-hosted) |
| `purchaseSpaceAccess` | `SpacesPurchaseService.swift:124` | Spaces checkout (payment intent path) |
| `stripeWebhookEntitlementHandler` | Referenced in `SpacesCore.swift:605` docs | Entitlement write on payment confirmation |

There is also no Stripe webhook `onRequest` handler (HTTP endpoint) in any deployed Cloud Function that would receive `payment_intent.succeeded`, `checkout.session.completed`, `customer.subscription.updated`, etc.

### 2. Apple Pay token is never processed

`GivingInAppSheet.swift:397–405` receives a `PKPayment` token and immediately calls `.success` without posting the token to any backend. This means:
- No payment is charged
- No Stripe PaymentIntent is created or confirmed
- User sees a success screen for a payment that never happened

### 3. Stripe iOS SDK is not integrated

The Stripe iOS SDK (`StripePayments`, `StripePaymentSheet`) is not present in the Xcode project. `Config.xcconfig` has no `STRIPE_PUBLISHABLE_KEY`. There is no `STPAPIClient.shared.publishableKey = ...` initialization. The `StripeGivingBridge` mentioned in the header comment of `GivingInAppSheet.swift` does not exist.

### 4. Refund flow is model-only

`StudioModels.swift` defines `RefundStatus` with `.requested`, `.approved`, `.denied`, `.processed` states but there is no Cloud Function implementing refund logic, no Stripe `refunds.create` call, and no UI path for a user to request a refund. Refund state is never written.

### 5. Recurring giving via Apple Pay not implemented

The app UI lets users pick Monthly/Annual frequency, but `PKPaymentRequest` uses static `paymentSummaryItems` without `PKRecurringPaymentRequest`. No subscription is created, no recurring billing token is sent to Stripe, and no recurring payment schedule is stored anywhere.

---

## Fix Recommendations

### Blocker 1: Deploy missing Stripe Cloud Functions

Create a `Backend/functions/src/stripe/` module with at minimum:

- `createStripeConnectedAccount` — calls `stripe.accounts.create({ type: 'express' })` and `stripe.accountLinks.create(...)`, stores `stripeAccountId` in Firestore. Verify Firebase Auth before running.
- `createCovenantCheckoutSession` — calls `stripe.checkout.sessions.create(...)` with `mode: 'subscription'`, `success_url: 'amen://covenant-checkout?result=success&membershipId={CHECKOUT_SESSION_ID}'`, `cancel_url: 'amen://covenant-checkout?result=cancel'`.
- `createSpaceCheckoutSession` — same pattern, writes `spaceId` in metadata.
- `purchaseSpaceAccess` — calls `stripe.paymentIntents.create(...)` with `application_fee_amount` for Connect, returns `clientSecret`.
- `stripeWebhook` (HTTP onRequest) — validates signature with `stripe.webhooks.constructEvent(rawBody, sig, secret)`, handles `payment_intent.succeeded`, `checkout.session.completed`, writes entitlements to Firestore via Admin SDK.

Export all from `index.ts` and deploy with:
```
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```

### Blocker 2: Fix Apple Pay token delivery

In `GivingInAppSheet.swift` `paymentAuthorizationController(_:didAuthorizePayment:handler:)`:
1. Convert `payment.token.paymentData` to base64 string.
2. Call a new Cloud Function `processGivingPayment` with `{ tokenBase64, amountCents, nonprofitId, recurringMode }`.
3. Only call `completion(.success)` and `onSuccess()` after the CF returns success.
4. On CF error, call `completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))`.

### Blocker 3: Wire "Donate with Card" fallback to Stripe payment sheet

Add the `StripePayments` and `StripePaymentSheet` SPM packages. In `GivingInAppSheet.swift`:
1. On "Donate with Card" tap, call a CF to create a PaymentIntent, get `clientSecret`.
2. Initialize `PaymentSheet(paymentIntentClientSecret:, configuration:)`.
3. Present via `PaymentSheet.FlowController` — never touch raw card data on the client.

### Blocker 4: Fix Apple Pay merchant ID entitlement mismatch

Either:
- Change `GivingInAppSheet.swift:363` from `"merchant.com.amen.giving"` to `"merchant.com.amen.app"` (to match the registered entitlement), OR
- Add `merchant.com.amen.giving` to `AMENAPP.entitlements` under `com.apple.developer.in-app-payments` and register it in Apple Developer Portal.

Both merchant IDs across all giving and Spaces flows must be registered and unified.

### Blocker 5: Add Stripe webhook HTTP endpoint

In Cloud Functions, add:
```typescript
export const stripeWebhook = onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  const secret = process.env.STRIPE_WEBHOOK_SECRET!;
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, secret);
  } catch (err) {
    res.status(400).send(`Webhook signature failed: ${err}`);
    return;
  }
  // Route event types: payment_intent.succeeded, checkout.session.completed,
  // customer.subscription.updated, customer.subscription.deleted, etc.
  // Write entitlements to Firestore via Admin SDK only here.
  res.json({ received: true });
});
```
Register the endpoint URL in Stripe Dashboard → Webhooks.

### High 1: Integrate Stripe iOS SDK

Add to `Package.swift` or Xcode SPM:
```
https://github.com/stripe/stripe-ios
```
In `AMENAPPApp.swift` or `AppDelegate.swift`, before any payment flow:
```swift
StripeAPI.defaultPublishableKey = Bundle.main.infoDictionary?["STRIPE_PUBLISHABLE_KEY"] as? String ?? ""
```
Add `STRIPE_PUBLISHABLE_KEY` to `Config.xcconfig` (publishable key only — never the secret key).

### High 2: Use PaymentSheet for Studio payments

When `StudioPaymentService.createPaymentIntent` returns `clientSecret`:
```swift
var config = PaymentSheet.Configuration()
config.merchantDisplayName = "AMEN"
let paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: config)
paymentSheet.present(from: viewController) { result in
    switch result {
    case .completed: // success
    case .canceled:  // user dismissed
    case .failed(let error): // show error
    }
}
```

### High 3: Implement receipt generation for nonprofit giving

Create a Cloud Function `issueGivingReceipt` triggered on `giving_sessions/{id}` status change to `completed`. It should:
1. Write a `GivingReceipt` document to `receipts/{receiptId}`.
2. Send a transactional email via SendGrid/Postmark (or Firebase Extensions) with tax receipt details.
3. Update the giving session `receiptId` field.

### Med 1: Extract platform fee to shared constant

Create `Backend/functions/src/shared/fees.ts`:
```typescript
export const PLATFORM_FEE_RATE = 0.02; // 2%
```
And in iOS, remove the hardcoded `0.02` literals. Replace both with a value fetched from Firebase Remote Config so it can be changed without an app update.

### Med 2: Apple IAP guideline 3.1.1 compliance review

The current payment matrix needs explicit review before App Store submission:

| Flow | Payment Method | Apple's Take | Status |
|------|---------------|--------------|--------|
| Berean Pro / Creator / Ministry Pro subscriptions | StoreKit 2 / RevenueCat IAP | 30% (15% for small devs) | Appears compliant — uses IAP |
| Covenant tier subscriptions | Stripe-hosted checkout (web) | **0%** — but this is only allowed for physical goods or out-of-app digital services. Subscription access to in-app content **requires IAP** under guideline 3.1.1 | **Potential rejection** |
| Space access purchases | Stripe payment intent | **0%** — same risk as above. In-app digital content access must use IAP | **Potential rejection** |
| Nonprofit donations (giving to registered 501(c)3) | Apple Pay / Stripe | **Exempt** under guideline 3.1.1 if org is a registered nonprofit. Verify each org has 501(c)3 status | Exempt if orgs are verified |
| Creator Studio commissions / products | Stripe Connect | Likely exempt as real-world services, but Apple may classify as digital goods if delivered in-app | **Review needed** |

**Recommendation:** Covenant subscriptions and Space purchases that grant in-app digital content access must be converted to StoreKit 2 products, or the content access must be delivered out-of-app (e.g., via web only). Consult Apple's guidelines or file a review request before shipping.

### Low 1: Add `prefersEphemeralWebBrowserSession = true` for Stripe checkout

In `CommunityStripeOnboardingView.swift`, `AmenCovenantCheckoutService.swift`, and `SpacesEntitlementService.swift`, set:
```swift
session.prefersEphemeralWebBrowserSession = true
```
This prevents accidental pre-fill from a cached Stripe dashboard session during financial identity verification and is aligned with Apple's own recommendation for payment/auth sessions.

### Low 2: Surface payout errors in StudioPaymentService

Add `@Published var payoutError: String?` to `StudioPaymentService`. In `requestPayout`, catch the error and write to `payoutError` rather than silently dropping it.

---

## PCI Compliance Summary

| Surface | Assessment |
|---------|-----------|
| Raw card numbers in Swift | Not found — no `UITextField` or field accepting PAN anywhere |
| Stripe secret key in iOS binary | Not found — no `sk_live`/`sk_test` in Swift source |
| Apple Pay token forwarding | **NOT implemented** — token is received but never forwarded to backend (Blocker 1) |
| Stripe iOS SDK present | Not integrated — PaymentSheet not available |
| PaymentIntent created server-side | Yes (when CFs are deployed) — `createPaymentIntent` is a server-side callable |
| Webhook signature verification | Not implemented — no webhook handler exists |

PCI compliance posture: the app **does not touch raw card data** (positive), but the Apple Pay integration is broken in a way that means no payment is ever processed at all. The webhook layer required to securely confirm payments server-side is entirely absent.

---

## Apple Pay Merchant ID Inventory

| Identifier | Location | Registered in Entitlements? |
|------------|----------|-----------------------------|
| `merchant.com.amen.app` | `AMENAPP.entitlements:17`, `AMENAPP.release.entitlements:17` | Yes |
| `merchant.com.amen.giving` | `GivingInAppSheet.swift:363` | **No** — mismatch with entitlement |

Both identifiers must be registered at developer.apple.com and in the entitlement file for Apple Pay to work.
