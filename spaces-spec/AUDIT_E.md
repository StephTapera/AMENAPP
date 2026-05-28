# AUDIT_E.md — Agent E Pre-Implementation Gap Report

> Date: 2026-05-28
> Agent: E (Monetization)

---

## 1. Existing Stripe Infrastructure

### 1.1 AmenCovenantCheckoutService.swift
**Path:** `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantCheckoutService.swift`

**Fee math:** NONE in this file. `AmenCovenantCheckoutService` handles checkout-session creation
and `ASWebAuthenticationSession` presentation. There is no fee-math function here.

**Reusable patterns:**
- `ASWebAuthenticationSession` already used; `presentationContextProvider` via `NSObject` conformance.
- Custom callback URL scheme `amen://` with query-param result parsing (`result=success`, `result=cancel`).
- `@MainActor final class` + `@Published var checkoutState` pattern.
- `defer { isLoading = false }` around async calls.
- CF callable: `createCovenantCheckoutSession` returns `{ checkoutUrl: String }`.

**Not reusable:** Covenant-specific membership IDs, Covenant-specific notification names,
`covenants` collection references. None of these bleed into Spaces.

### 1.2 AmenCovenantManageView.swift
**Path:** `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantManageView.swift`

**Reusable UX patterns:**
- Horizontal stats strip (glass cards with value + label + icon).
- `ultraThinMaterial` cards with `RoundedRectangle(cornerRadius: 22)` + shadow.
- Tool-tile grid: 2-column `LazyVGrid`, glass card per tool.
- Revenue item in the tools grid routes to analytics.
- `@StateObject private var manageVM = AmenCovenantManageViewModel()` pattern.
- `AmenCovenantManageViewModel` shows `async withTaskGroup` parallel loading.

**Not reusable:** `Covenant`, `CovenantOperatingMode` types, `covenants` collection path.

### 1.3 functions/stripeFunctions.js (root)
**Path:** `functions/stripeFunctions.js`

Contains `stripeCreateConnectedAccount` (for Creator Studio users, keyed to `users/` collection).
Platform fee is 5% in this file. NOT suitable to reuse directly — writes to wrong collections,
uses JS not TS, and is Creator Studio-scoped, not Spaces-community-scoped.

**Pattern reuse:** account-creation flow (create Express account → generate account link) is the
correct Stripe API sequence; the TS implementation will follow the same calls.

---

## 2. Existing Fee Math Location

**The fee math lives in:** `AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift`
(the Agent C/pre-built Spaces layer, `AMENAPP/Spaces/Monetization/`)

**Function signatures (the source of truth):**
```swift
static func creatorPayout(amountCents: Int) -> Int
// Deducts platform fee (2%) + Stripe fee (2.9% + $0.30)
// Returns max(0, floor(payout))

static func payoutLabel(amountCents: Int) -> String
// "~$X.XX goes to creator"

static func priceLabel(config: PriceConfig) -> String
// "$X.XX" | "$X.XX/month" | "$X.XX/year"

static func intervalDescription(config: PriceConfig) -> String
// "One-time access" | "Monthly" | "Yearly"
```

`SpacesEntitlementService.swift` (the new `AMENAPP/AMENAPP/Spaces/Monetization/` layer)
wraps via thin delegation to the existing calculator. No math is forked.

---

## 3. Existing ASWebAuthenticationSession Usage

`AmenCovenantCheckoutService.swift` demonstrates the full `ASWebAuthenticationSession` pattern
including `presentationContextProvider` conformance. The Spaces `CommunityStripeOnboardingView`
calls an identical service-class pattern.

---

## 4. Existing Spaces Monetization Pre-builds

**`AMENAPP/Spaces/Monetization/` already contains:**
- `SpacesFeeCalculator.swift` — fee math (source of truth, do NOT duplicate)
- `SpacesPurchaseService.swift` — async purchase orchestration using `EntitlementService.observeEntitlement`
- `SpacesPurchaseSheet.swift` — glass purchase sheet wired to `LockedPreviewShell`
- `AdminGrantView.swift` — admin comp/grant sheet

These are Agent C-layer pre-builds. The deliverables for Agent E live in
`AMENAPP/AMENAPP/Spaces/Monetization/` (a separate layer keyed to the `SpacesModels.swift`
types in `AMENAPP/AMENAPP/Spaces/`).

---

## 5. Entitlement Infrastructure

`EntitlementService` with `AsyncStream<SpaceEntitlement?>` already exists in
`AMENAPP/Spaces/SpacesEntitlementModels.swift`. The new `SpacesEntitlementService`
wraps `SpacesService.shared` (which provides `fetchEntitlement`, `entitlementListener`,
`hasAccess`, `fetchMyActiveEntitlements`).

---

## 6. Missing Cloud Functions

**`functions/src/spaces/createSpaceCheckoutSession.ts`** — does NOT exist. Must build.
**`functions/src/spaces/createStripeConnectAccount.ts`** — does NOT exist. Must build.

---

## 7. Gaps to Close

| Gap | Action |
|---|---|
| No `SpacesEntitlementService.swift` in AMENAPP/AMENAPP/Spaces/Monetization/ | Build |
| No `SpaceEntitlementViewModel.swift` | Build |
| No `SpaceLockedView.swift` | Build |
| No `CommunityStripeOnboardingView.swift` | Build |
| No `SpacesFeeCalculator.swift` in AMENAPP/AMENAPP/Spaces/Monetization/ | Build thin wrapper delegating to existing |
| No `SpaceRevenueCard.swift` | Build |
| No `createSpaceCheckoutSession.ts` | Build |
| No `createStripeConnectAccount.ts` | Build |

---

## 8. Hard-constraint Checks

- `allow write: if false` on entitlements — confirmed in Contract A §5. Client reads only.
- Money never crosses community Link — confirmed. `createSpaceCheckoutSession` routes to owning community's Connect account only.
- No "church" in any identifier — confirmed.
- ASWebAuthenticationSession pattern — confirmed present in `AmenCovenantCheckoutService`.
- Existing fee math not forked — confirmed, thin wrapper will call through.
