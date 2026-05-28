# CONTRACT_E.md — Spaces Monetization Layer
> Agent E deliverables. All downstream agents (B, C, D, F) may build against this contract.
> Do not redefine any type listed here.

---

## Fee Audit Report (mandatory read)

Before building, Agent E audited:
- `GivingInAppSheet.swift`: `platformFee = effectiveAmount * 0.02` (2%). No Stripe fee on iOS side.
- `AmenCovenantCheckoutService.swift`: Uses Stripe-hosted checkout; no fee math on client.

**Decision:** `SpacesFeeCalculator` uses `platformFeeRate: 0.02` (exact match to GivingInAppSheet).
Stripe fees (2.9% + $0.30) are backend-only; exposed in `SpacesFeeCalculator` for payout-label accuracy.
The payout label is shown to users as a creator transparency feature, not a buyer-facing charge.

---

## File Locations

| File | Path |
|------|------|
| `SpacesFeeCalculator` | `AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift` |
| `SpacesPurchaseService` | `AMENAPP/Spaces/Monetization/SpacesPurchaseService.swift` |
| `SpacesPurchaseSheet` | `AMENAPP/Spaces/Monetization/SpacesPurchaseSheet.swift` |
| `AdminGrantView` | `AMENAPP/Spaces/Monetization/AdminGrantView.swift` |
| `purchaseSpaceAccess` CF | `Backend/functions/src/spaces/purchaseService.ts` |

---

## SpacesFeeCalculator Public API

```swift
enum SpacesFeeCalculator {
    static let platformFeeRate: Double = 0.02   // matches GivingInAppSheet exactly
    static let stripeFeeRate: Double = 0.029    // 2.9% — backend concern
    static let stripeFixedFee: Int = 30         // $0.30 — backend concern

    /// Creator net payout in cents. Never negative.
    static func creatorPayout(amountCents: Int) -> Int

    /// "~$X.XX goes to creator"
    static func payoutLabel(amountCents: Int) -> String

    /// "$X.XX" | "$X.XX/month" | "$X.XX/year"
    static func priceLabel(config: PriceConfig) -> String

    /// "One-time access" | "Monthly" | "Yearly"
    static func intervalDescription(config: PriceConfig) -> String
}
```

---

## SpacesPurchaseService Method Signatures

```swift
@MainActor
final class SpacesPurchaseService: ObservableObject {
    @Published var isPurchasing: Bool
    @Published var purchaseError: String?
    @Published var entitlement: SpaceEntitlement?
    @Published var pendingClientSecret: String?  // present Stripe sheet with this

    func purchaseSpace(_ space: AmenSpaceExtended, userId: String) async throws
    func startObservingEntitlement(userId: String, spaceId: String)
    func stopObserving()
    var hasActiveAccess: Bool  // true when status == .active || .grace
}
```

`SpacesPurchaseError` cases: `policyNotPurchasable`, `missingSpaceId`, `missingPriceConfig`,
`networkError(Error)`, `invalidServerResponse`, `userNotAuthenticated`.

---

## SpacesPurchaseSheet Entry Point

```swift
SpacesPurchaseSheet(
    space: AmenSpaceExtended,      // the space being unlocked
    userId: String,                // current Firebase Auth uid
    isPresented: Binding<Bool>     // sheet is dismissed when entitlement becomes .active
)
```

### LockedPreviewShell Wiring (Agent C)

```swift
// In Agent C's LockedPreviewShell, wire the unlock trigger like this:
@State private var isPurchaseSheetPresented = false

// Inside LockedPreviewShell.body:
.sheet(isPresented: $isPurchaseSheetPresented) {
    SpacesPurchaseSheet(
        space: space,
        userId: userId,
        isPresented: $isPurchaseSheetPresented
    )
}

// The unlock CTA in LockedPreviewShell calls:
isPurchaseSheetPresented = true
```

`SpacePurchasePresenting` is a bridge protocol in `SpacesPurchaseSheet.swift`.
When C's concrete type exists, callers may remove the protocol bridge.

---

## AdminGrantView Entry Point

```swift
AdminGrantView(
    spaceId: String,
    targetUserId: String,
    isPresented: Binding<Bool>
)
```

Caller MUST verify the current user is `owner` or `admin` in `spaces/{spaceId}/members/{userId}`
before presenting. The CF (`grantAccess`) re-validates server-side — this is defense in depth.

---

## Entitlement State → UI State Map

| `EntitlementStatus` | UI state | Notes |
|---|---|---|
| `nil` (no doc) | C's LockedPreviewShell renders | User has never purchased or been granted |
| `.active` | Full Space content visible | Normal paid access |
| `.grace` | Content visible + "Renewal needed" banner | Payment lapsed, grace window active |
| `.expired` | C's LockedPreviewShell renders with `onUnlock` → SpacesPurchaseSheet | Re-purchase or contact admin |

Status flips only. Entitlement documents are never hard-deleted.

---

## `purchaseSpaceAccess` Callable — Input / Output Shape

This is the canonical shape for Agent D's wizard to record `priceConfig` correctly.

### Input
```typescript
{
  spaceId: string,       // Firestore document ID of the space
  userId: string,        // Firebase Auth uid of the buyer (must match caller)
  communityId: string,   // owning community — must match spaces/{spaceId}.communityId
  priceConfig: {
    amountCents: number, // e.g. 999 = $9.99 — integer, > 0
    currency: string,    // ISO 4217 lowercase, e.g. "usd"
    interval?: string,   // "month" | "year" — required for recurring; omit for oneTime
  }
}
```

### Output
```typescript
{ clientSecret: string }
```

The iOS client passes `clientSecret` to the Stripe payment sheet.
Stripe confirms payment → triggers `payment_intent.succeeded` (oneTime) or
`customer.subscription.updated` (recurring) webhook →
`stripeWebhookEntitlementHandler` writes `entitlements/{userId}_{spaceId}`.

### Agent D Notes
- `priceConfig.amountCents` must match what the creator set in the wizard's access step
- `priceConfig.interval` must be `"month"` or `"year"` for recurring spaces
- Omit `interval` (or set to `null`) for one-time access spaces
- `communityId` is always the **owning** community's ID — never a linked community

---

## 3-Line Handoff

**What changed:** 4 Swift files in `AMENAPP/Spaces/Monetization/`, 1 TypeScript CF in `Backend/functions/src/spaces/purchaseService.ts`, `spaces/index.ts` updated to export `purchaseSpaceAccess`.

**Contract exposed:** `SpacesFeeCalculator` (fee math, payout labels), `SpacesPurchaseService` (purchase + live entitlement), `SpacesPurchaseSheet(space:userId:isPresented:)` (glass unlock UI), `AdminGrantView(spaceId:targetUserId:isPresented:)` (comp path), `purchaseSpaceAccess` CF (Stripe PaymentIntent / Subscription on Connect account).

**Assumptions:** (1) Stripe SDK is already present in the Xcode project for payment sheet confirmation — `pendingClientSecret` is published for UI layer to consume. (2) `SpacesFeeCalculator.platformFeeRate` exactly matches `GivingInAppSheet.swift`'s `0.02`. (3) Agent C's `LockedPreviewShell` will call `isPurchaseSheetPresented = true`; `SpacePurchasePresenting` protocol bridges the gap until C's type is available. (4) External/linked members use the grant path (`AdminGrantView` → `grantAccess` CF); they never reach `purchaseSpaceAccess`.
