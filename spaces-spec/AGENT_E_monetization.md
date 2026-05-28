# Agent E — Monetization (Stripe Connect per-Space, Entitlement Purchase, Paywall UI)

> Read `00_MASTER_CONTRACT.md` and `CONTRACT_A.md` first. You depend only on Agent A —
> you can start as soon as A is complete, in parallel with B and C. Project root:
> `~/Desktop/AMEN/AMENAPP copy/`, workspace `AMENAPP.xcworkspace`.

## Your mandate

You build the per-Space monetization layer: one-time and recurring Stripe purchases,
entitlement issuance, the locked-preview paywall, and the community's Stripe Connect
onboarding flow.

### Step 1 — AUDIT FIRST (gap report before changing anything)

Inventory existing Stripe + monetization infrastructure:
- Check `AMENAPP/AMENAPP/Covenant/` — this is the existing Covenant monetization
  system. Read `AmenCovenantCheckoutService.swift` and `AmenCovenantManageView.swift`.
  Map what is reusable vs. what is Covenant-specific and cannot be shared.
- Check `Giving/` at the project root for any giving/payment flow.
- Find the existing **Stripe fee math** function (probably in `AmenCovenantCheckoutService`
  or a `StripeService`). This is the one D's wizard also needs — document the exact
  function signature in CONTRACT_E.md so D can import it.
- Check `functions/` for existing Stripe webhook handlers and Connect account creation
  functions.
- Look for existing `stripeConnectAccountId` usage to understand how Connect accounts are
  currently linked to entities.

Produce a gap report: what is reusable, what conflicts, what is missing.

### Step 2 — Community Stripe Connect onboarding

A community's owner must complete Stripe Connect onboarding before creating paid Spaces.

**`AMENAPP/AMENAPP/Spaces/Monetization/CommunityStripeOnboardingView.swift`**
```swift
// Presented when owner taps "Enable paid Spaces" in community settings.
// Uses existing Stripe Connect account creation flow if it exists.
// If not: Cloud Function creates a Stripe Connect account + returns onboarding link.
// Opens the Stripe Connect onboarding URL in ASWebAuthenticationSession (or SFSafariViewController).
// On return: check account status, write stripeConnectAccountId to communities/{communityId}.
// Show: "Your account is ready" glass card when complete.
struct CommunityStripeOnboardingView: View { ... }
```

**`functions/src/spaces/createStripeConnectAccount.ts`** (if not already handled)
```typescript
// Callable: { communityId: string }
// Creates Stripe Express account, returns { accountId, onboardingURL }.
// Writes communities/{communityId}.stripeConnectAccountId.
// Validates caller is owner of the community.
```

### Step 3 — Per-Space purchase flow

**`AMENAPP/AMENAPP/Spaces/Monetization/SpacesEntitlementService.swift`** (async/await, no Combine)
```swift
// hasActiveEntitlement(userId: String, spaceId: String) async throws -> Bool
//   → reads entitlements/{userId}_{spaceId}, checks status: active | grace
// purchaseAccess(spaceId: String) async throws
//   → calls Cloud Function createSpaceCheckoutSession
//   → opens payment UI (StoreKit / Stripe, matching existing checkout pattern)
//   → on success: entitlements/{userId}_{spaceId} is written by the CF (not the client)
// fetchEntitlement(userId: String, spaceId: String) async throws -> SpaceEntitlement?
// streamEntitlement(userId: String, spaceId: String) -> AsyncStream<SpaceEntitlement?>
//   → real-time listener so paywall unlocks the moment payment completes
```

**`functions/src/spaces/createSpaceCheckoutSession.ts`**
```typescript
// Callable: { spaceId: string }
// Validates space exists, has priceConfig, and the calling user is not already entitled.
// Creates Stripe Checkout session or PaymentIntent against the community's Connect account.
// For recurring: creates Stripe Subscription.
// On Stripe webhook success (handled by Agent A's webhook CF):
//   writes entitlements/{userId}_{spaceId} with status: "active".
// Returns: { checkoutURL } or { clientSecret } for in-app payment sheet.
```

### Step 4 — Paywall / locked-preview UI

**`AMENAPP/AMENAPP/Spaces/Monetization/SpaceLockedView.swift`**

This is imported by Agent C's `SpaceDetailView` when a paid Space has no active entitlement.

```swift
// Layout:
// - Blurred preview of the last N public messages (teaser, read-only, max 3 messages).
// - Glass card overlaid on the blur:
//     Space avatar + title
//     Pricing: "$X one-time" or "$X/month"
//     Creator name + community name
//     [Unlock Space] button — amenGold
//     [Restore Purchase] link (for one-time only)
// - Spring animation when unlocked (the glass card dissolves into the chat view).
// Parameters: space: Space, onPurchaseTapped: () -> Void, onRestoreTapped: () -> Void

struct SpaceLockedView: View { ... }
```

**`AMENAPP/AMENAPP/Spaces/Monetization/SpaceEntitlementViewModel.swift`** (@MainActor)
```swift
@MainActor
final class SpaceEntitlementViewModel: ObservableObject {
    @Published var entitlementState: EntitlementState = .unknown
    // EntitlementState: unknown | checking | active | grace | expired | notRequired

    func checkEntitlement(for spaceId: String) async
    func purchase(spaceId: String) async
    func restore(spaceId: String) async
    // Streams real-time changes so the paywall lifts automatically on payment.
}
```

### Step 5 — Grace period + revocation handling

When `SpaceEntitlementService` observes `status: "grace"`:
- Show a non-blocking banner in `SpaceDetailView` (imported by C):
  ```
  "Your subscription payment is processing — you still have access."
  ```
- After grace period ends (Agent A's webhook flips to `expired`):
  - The `AsyncStream<SpaceEntitlement?>` emits the change.
  - `SpaceEntitlementViewModel.entitlementState` updates to `.expired`.
  - `SpaceDetailView` (C) re-routes to `SpaceLockedView`.
  - No hard-delete, no crash. The view transitions cleanly.

### Step 6 — Revenue display for community owner

**`AMENAPP/AMENAPP/Spaces/Monetization/SpaceRevenueCard.swift`**
```swift
// A card shown in Space settings (owner/admin only).
// Shows: total revenue from this Space, active subscriber count, one-time purchases.
// Data: callable → queries Stripe Connect account's balance for the Space's product.
// Reuses AmenGold color and the existing revenue/analytics card style if one exists.
struct SpaceRevenueCard: View { ... }
```

**Stripe fee math export**

Find the existing fee math function and export it as:
```swift
// SpacesStripeFeeCalculator.swift (or extend existing)
struct SpacesFeeCalculator {
    static func netAmount(grossCents: Int, currency: String) -> Int
    static func feePreviewString(grossCents: Int, currency: String) -> String
    // e.g. "You'll receive ~$9.12 after fees" for a $9.99 product
}
```
If the existing fee math lives in Covenant or another module, create a thin wrapper that
calls through. Do NOT duplicate the math.

---

## Hard constraints

- Money never crosses a community Link. The Connect account is the owning community's.
- Entitlement writes happen in Cloud Functions only (or Firestore admin SDK). The client
  READS entitlements, does not write them after purchase — the webhook/CF does.
- `SpaceLockedView` must dissolve gracefully when entitlement activates — no hard dismiss.
- Use AsyncStream for real-time entitlement state, not polling.
- No Combine. Async/await only.
- No hard-deletes.
- No "church" in any string or label.
- The fee math function exposed in CONTRACT_E must be the existing one, not a new one.

---

## Deliverables

1. `AMENAPP/AMENAPP/Spaces/Monetization/SpacesEntitlementService.swift`
2. `AMENAPP/AMENAPP/Spaces/Monetization/SpaceEntitlementViewModel.swift`
3. `AMENAPP/AMENAPP/Spaces/Monetization/SpaceLockedView.swift`
4. `AMENAPP/AMENAPP/Spaces/Monetization/CommunityStripeOnboardingView.swift`
5. `AMENAPP/AMENAPP/Spaces/Monetization/SpaceRevenueCard.swift`
6. `AMENAPP/AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift` (or wrapper)
7. `functions/src/spaces/createSpaceCheckoutSession.ts`
8. `functions/src/spaces/createStripeConnectAccount.ts` (if not already exists)
9. **`spaces-spec/CONTRACT_E.md`** — `SpacesEntitlementService` public interface,
   `SpaceLockedView` parameters, fee math function signature (so D can import it),
   any shared files touched.

---

## Done when

- All Swift files build with zero diagnostics.
- `SpaceLockedView` renders and unlocks via real-time entitlement stream.
- Fee math is the existing calculation, not a fork.
- `CONTRACT_E.md` published ending with "AGENT_E_COMPLETE".
