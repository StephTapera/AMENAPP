# Covenant Payments — Deployment Checklist

Run through every item below before executing `firebase deploy`.
Each section maps to a failure mode that has burned production deployments.

---

## 1. Firebase Project Configuration

- [ ] **Target project confirmed** — run `firebase use` and verify the project ID matches prod  
- [ ] **App Check enforced** — `enforceAppCheck: true` is set on `createCovenantCheckoutSession` and `saveCovenantTierStripePriceId`. Confirm App Check is enabled in the Firebase Console for both iOS and the Functions service.

---

## 2. Environment Secrets (Firebase Functions Config)

Both secrets must be set before deploying. Verify with:

```bash
firebase functions:secrets:access STRIPE_SECRET_KEY
firebase functions:secrets:access STRIPE_COVENANT_WEBHOOK_SECRET
```

- [ ] **`STRIPE_SECRET_KEY`** — Live secret key (`sk_live_...`). Never the test key in prod.  
- [ ] **`STRIPE_COVENANT_WEBHOOK_SECRET`** — From Stripe Dashboard → Developers → Webhooks → your endpoint's signing secret (`whsec_...`).

To set:
```bash
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_COVENANT_WEBHOOK_SECRET
```

---

## 3. Stripe Dashboard — Webhook Registration

- [ ] **Endpoint registered** — `https://<region>-<project>.cloudfunctions.net/stripeCovenantWebhook`  
- [ ] **All required events selected**:
  - `checkout.session.completed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
- [ ] **Webhook is in "Live mode"** if deploying to production  
- [ ] **Signing secret copied** and set as `STRIPE_COVENANT_WEBHOOK_SECRET` (see §2)

---

## 4. Stripe Products & Prices

Before any creator can go live with paid tiers:

- [ ] **Product created in Stripe** for each paid tier  
- [ ] **Recurring Price created** with the correct currency, amount, and billing interval  
- [ ] **Price IDs (`price_xxx`)** entered by the creator in-app via **Manage → Tiers** (`AmenCovenantTierSetupSheet`)  
- [ ] **No test Price IDs in production** — `price_test_...` IDs are rejected by live mode Stripe

---

## 5. Firestore Rules

Confirm the rules allow:

- [ ] `covenants/{covenantId}/members/{uid}` **write** — only backend (no client write rule)  
- [ ] `covenants/{covenantId}/tiers` update — restricted to `isCreatorOf()` via `saveCovenantTierStripePriceId` CF; rule should block direct client writes to `tiers`  
- [ ] **Deploy rules** if any changes were made:  
  ```bash
  firebase deploy --only firestore:rules,firestore:indexes
  ```

---

## 6. iOS Client

- [ ] **`AmenCovenantCheckoutService.startCheckout()`** calls `createCovenantCheckoutSession` (not a direct Stripe call)  
- [ ] **Deep link handler** registered for `amen://covenant-checkout` scheme in `Info.plist`  
- [ ] **`ASWebAuthenticationSession` result** handled: `result=success` refreshes membership; `result=cancel` dismisses gracefully  
- [ ] **`enforceAppCheck: true`** — App Check token is attached by the Firebase iOS SDK automatically for `onCall` functions

---

## 7. Exports Verified

All three new functions must appear in `src/index.ts`:

```ts
export * from "./covenant/createCovenantCheckoutSession";
export * from "./covenant/saveCovenantTierStripePriceId";
// stripeCovenantWebhook is exported from stripeCovenantWebhook.ts (already in index)
```

Verify:
```bash
grep -n "covenant" src/index.ts
```

---

## 8. Tests Pass

```bash
cd Backend/functions
npm ci
npm test
```

Expected: **25 tests pass, 0 failures** across:
- `src/covenant/stripeCovenantWebhook.test.ts` (17 tests)
- `src/covenant/createCovenantCheckoutSession.test.ts` (8 tests)

---

## 9. Deploy Commands

```bash
# Deploy all three functions (+ any other changes in index.ts)
firebase deploy --only functions

# Or deploy individually if you want to minimize blast radius:
firebase deploy --only functions:stripeCovenantWebhook
firebase deploy --only functions:createCovenantCheckoutSession
firebase deploy --only functions:saveCovenantTierStripePriceId
```

---

## 10. Post-Deploy Smoke Test

- [ ] **Trigger a test checkout** with a Stripe test clock or test card  
- [ ] **Verify Stripe webhook delivery** — Stripe Dashboard → Developers → Webhooks → recent deliveries shows 200 responses  
- [ ] **Verify member index written** — Firestore Console → `covenants/{id}/members/{uid}` doc exists with `status: "active"`  
- [ ] **Verify `saveCovenantTierStripePriceId`** — open Manage → Tiers in the iOS app, enter a price ID, confirm Firestore covenant doc shows updated `tiers[].stripePriceId`

---

## Go / No-Go

| Check | Status |
|---|---|
| Both secrets set in Firebase | |
| Webhook registered with all 4 events | |
| At least one real Stripe Price ID configured for a tier | |
| All 25 unit tests pass | |
| Firestore rules deployed | |
| iOS deep link handler wired | |
