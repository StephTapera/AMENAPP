# CONTRACT_E — Spaces Monetization
# Agent E deliverables: public interfaces for Agent D (creation wizard) and Agent C (detail view).

---

## 1. SpacesEntitlementService — public interface

File: `AMENAPP/AMENAPP/Spaces/Monetization/SpacesEntitlementService.swift`

```swift
@MainActor
final class SpacesEntitlementService: NSObject, ObservableObject {

    static let shared: SpacesEntitlementService

    /// Cached entitlement state per spaceId (keyed by spaceId String).
    @Published var entitlementsBySpace: [String: SpaceEntitlement]

    /// Returns true if the current Firebase user has active or grace entitlement.
    func hasActiveEntitlement(spaceId: String) async throws -> Bool

    /// Opens the Stripe Checkout flow for a paid Space.
    /// Calls CF `createSpaceCheckoutSession` → opens ASWebAuthenticationSession (scheme: "amen").
    /// Entitlement is written by the webhook CF — never by this client method.
    func purchaseAccess(space: AmenSpace) async throws

    /// Refreshes entitlement state from Firestore for one-time purchases.
    func restorePurchase(spaceId: String) async throws

    /// Starts a real-time Firestore snapshot listener.
    /// Updates entitlementsBySpace[spaceId] on every document change.
    func startListening(userId: String, spaceId: String)

    /// Cancels the real-time listener for a space.
    func stopListening(spaceId: String)
}
```

**Error type:** `SpacesEntitlementError: LocalizedError`
```swift
enum SpacesEntitlementError: LocalizedError {
    case notAuthenticated       // "You must be signed in to access paid Spaces."
    case spaceNotPurchasable    // "This Space does not require a purchase."
    case missingPriceConfig     // "This Space does not have a price configured."
    case invalidServerResponse  // "Received an unexpected response. Please try again."
    case checkoutCanceled       // "Checkout was canceled."
    case network(Error)
}
```

**Notification posted on checkout success** (for edge-case observers):
```swift
Notification.Name.spacesCheckoutSucceeded  // "spacesCheckoutSucceeded"
```

---

## 2. SpaceEntitlementViewModel — public interface

File: `AMENAPP/AMENAPP/Spaces/Monetization/SpaceEntitlementViewModel.swift`

```swift
@MainActor
final class SpaceEntitlementViewModel: ObservableObject {

    enum EntitlementState: Equatable {
        case unknown     // initial — not yet checked
        case checking    // async check in flight
        case active      // user has access
        case grace       // payment processing / subscription lapsing — still has access
        case expired     // no entitlement — show paywall
        case notRequired // space.accessPolicy == .free
    }

    @Published var state: EntitlementState       // drives paywall visibility
    @Published var isPurchasing: Bool            // drives loading indicator on Unlock button
    @Published var purchaseError: Error?         // surface to user on purchase failure

    init(service: SpacesEntitlementService = .shared)

    /// Checks entitlement and starts real-time listener. Call on view appear.
    func check(space: AmenSpace) async

    /// Initiates purchase flow. Fires purchaseError on failure.
    func purchase(space: AmenSpace) async

    /// Refreshes one-time purchase from Firestore.
    func restore(space: AmenSpace) async

    /// Cancels real-time listener. Call on view disappear.
    func stopListening(spaceId: String)
}
```

---

## 3. SpaceLockedView — parameters

File: `AMENAPP/AMENAPP/Spaces/Monetization/SpaceLockedView.swift`

```swift
struct SpaceLockedView: View {
    /// The paid Space being gated.
    let space: AmenSpace
    /// Shared with the parent SpaceDetailView — drives unlock animation.
    @ObservedObject var viewModel: SpaceEntitlementViewModel
}
```

**Usage in Agent C's SpaceDetailView:**
```swift
// When viewModel.state == .expired or .checking, show SpaceLockedView.
// When viewModel.state == .active, show the chat/study content.
// SpaceLockedView handles its own .task { await viewModel.check(space: space) }.

SpaceLockedView(space: space, viewModel: entitlementViewModel)
```

**Unlock animation:** glass card `.opacity` and `.scaleEffect` animate to 0 / 0.92 when
`viewModel.state == .active`. The parent must keep `SpaceLockedView` in the view hierarchy
briefly to allow the spring dissolve to complete before removing it.

**Grace banner:** automatically shown inside `SpaceLockedView` when `viewModel.state == .grace`.
Agent C does not need to render a separate banner.

---

## 4. CommunityStripeOnboardingView — parameters

File: `AMENAPP/AMENAPP/Spaces/Monetization/CommunityStripeOnboardingView.swift`

```swift
struct CommunityStripeOnboardingView: View {
    /// The Firestore document ID of the community (from amenCommunities/{communityId}).
    let communityId: String
    /// Dismiss binding — set to false when onboarding is complete or canceled.
    @Binding var isPresented: Bool
}
```

**Present from community settings (owner only):**
```swift
.sheet(isPresented: $showStripeOnboarding) {
    CommunityStripeOnboardingView(communityId: community.id, isPresented: $showStripeOnboarding)
}
```

---

## 5. SpaceRevenueCard — parameters

File: `AMENAPP/AMENAPP/Spaces/Monetization/SpaceRevenueCard.swift`

```swift
struct SpaceRevenueCard: View {
    /// The Space whose revenue to display.
    let space: AmenSpace
    /// The owning community's Firestore ID.
    let communityId: String
}
```

**Visibility:** caller (Space settings sheet) MUST verify current user is owner or admin
before presenting. The card itself does not perform role checks.

---

## 6. Fee Math — SpacesFeeCalculatorE (Agent D's import target)

File: `AMENAPP/AMENAPP/Spaces/Monetization/SpacesFeeCalculatorE.swift`

**This is a thin wrapper.** All math delegates to the canonical
`SpacesFeeCalculator` in `AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift`.

```swift
enum SpacesFeeCalculatorE {

    /// Creator net payout in cents after all fees.
    /// Delegates to SpacesFeeCalculator.creatorPayout(amountCents:).
    /// Formula: amount - (amount * 0.02) - (amount * 0.029 + 30)
    static func netAmountCents(grossCents: Int) -> Int

    /// Human-readable payout estimate for the creation wizard.
    /// Example output: "You'll receive ~$9.40 after fees" for grossCents=999, currency="usd"
    static func feePreviewString(grossCents: Int, currency: String) -> String

    /// "$X.XX" | "$X.XX/month" | "$X.XX/year" — delegates to SpacesFeeCalculator.priceLabel
    static func priceLabel(config: PriceConfig) -> String

    /// "One-time access" | "Monthly" | "Yearly" — delegates to SpacesFeeCalculator.intervalDescription
    static func intervalDescription(config: PriceConfig) -> String

    /// Read-only mirror of platform fee rate (2.0%). DO NOT use for calculation.
    static var platformFeeRate: Double   // 0.02
}
```

**Canonical fee rates (from SpacesFeeCalculator):**
- Platform fee: 2.0% (`platformFeeRate = 0.02`)
- Stripe processing: 2.9% + $0.30 (`stripeFeeRate = 0.029`, `stripeFixedFee = 30`)
- Net = grossCents × (1 − 0.02) − grossCents × 0.029 − 30
- Example: $9.99 → 999 × 0.951 = 950.049 − 30 = 920.049 → floor → **920 cents ($9.20)**

---

## 7. Cloud Functions — public contracts

### createSpaceCheckoutSession
```typescript
// Callable: { spaceId: string }
// Auth: required + App Check enforced
// Secrets: STRIPE_SECRET_KEY
//
// Returns: { checkoutURL: string }
//
// Errors:
//   unauthenticated    — no Firebase user
//   invalid-argument   — missing/empty spaceId
//   not-found          — space or community does not exist
//   invalid-argument   — space.accessPolicy == "free"
//   failed-precondition — space has no priceConfig
//   failed-precondition — community has no stripeConnectAccountId
//   already-exists     — caller already has active/grace entitlement
//   internal           — Stripe did not return a URL
//
// Stripe metadata set (required for webhook routing):
//   metadata.amenUserId  = callerUid
//   metadata.amenSpaceId = spaceId
//   (also set on subscription_data.metadata and payment_intent_data.metadata)
```

### createStripeConnectAccount
```typescript
// Callable: { communityId: string }
// Auth: required + App Check enforced
// Secrets: STRIPE_SECRET_KEY
//
// Returns: { accountId: string, onboardingURL: string }
//
// Errors:
//   unauthenticated  — no Firebase user
//   invalid-argument — missing/empty communityId
//   not-found        — community does not exist
//   permission-denied — caller is not community owner
//
// Side effect: writes stripeConnectAccountId to amenCommunities/{communityId}
// Idempotent: if stripeConnectAccountId already exists, returns new account link.
```

---

## 8. Firestore paths used

| Collection | Document ID | Notes |
|---|---|---|
| `entitlements` | `{userId}_{spaceId}` | Flat top-level. Client READ only. |
| `spaces` | `{spaceId}` | `accessPolicy`, `priceConfig`, `communityId` |
| `amenCommunities` | `{communityId}` | `stripeConnectAccountId`, `ownerUserId` |
| `amenCommunities/{communityId}/members` | `{userId}` | `role: "owner"` fallback check |

---

## 9. Shared files touched by Agent E

| File | Change |
|---|---|
| `AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift` | **NOT changed** — canonical fee math preserved |
| `functions/src/spaces/index.ts` | Added two exports: `createSpaceCheckoutSession`, `createStripeConnectAccount` |

---

## 10. Integration checklist for Agent C (SpaceDetailView)

1. Instantiate `SpaceEntitlementViewModel` as `@StateObject` in `SpaceDetailView`.
2. When `viewModel.state == .expired || viewModel.state == .unknown`:
   - Show `SpaceLockedView(space: space, viewModel: viewModel)`.
3. When `viewModel.state == .active || viewModel.state == .notRequired`:
   - Show chat/study content.
4. `SpaceLockedView` calls `viewModel.check(space:)` on `.task` — no need to call it from parent.
5. Call `viewModel.stopListening(spaceId:)` on parent `onDisappear`.

## 11. Integration checklist for Agent D (creation wizard)

1. Import `SpacesFeeCalculatorE` — call `feePreviewString(grossCents:currency:)` in the price picker.
2. When `priceConfig.interval == "month" | "year"`, `accessPolicy = .recurring`.
3. When `priceConfig.interval == nil`, `accessPolicy = .oneTime`.
4. Do NOT write `entitlements/` from the creation wizard.
5. Do NOT write `stripeConnectAccountId` — it is server-owned.

---

AGENT_E_COMPLETE
