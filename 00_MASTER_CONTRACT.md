# 00_MASTER_CONTRACT.md — AMEN Spaces Master Contract
> Written by Orchestrator. Read this before any work. All agents must respect every boundary here.

---

## What we're building
AMEN **Spaces** — Slack channels + Outlook/Teams org + Patreon monetization, in AMEN's Liquid Glass design language, powered by Berean AI. Faith-oriented but NOT church-specific. The collaborating unit is a generic **Community** (church, Bible study, family, small group, ministry).

**No field, enum, string, label, or comment may hardcode "church."**

---

## Project root
`~/Desktop/AMEN/AMENAPP copy/`  
Workspace: `AMENAPP.xcworkspace`  
Backend: `Backend/functions/src/`

---

## Existing infrastructure — reuse, don't fork

### Phase 0 Spaces contracts (authoritative, do not redefine)
- `AMENAPP/Spaces/SpacesCore.swift` — `AmenSpaceV2`, `AmenRoom`, `AmenRoomPost`, `AmenSpaceRoleType` (18 roles), `AmenGiftType` (16 gifts), `AmenSpaceMembershipV2`, `AmenModerationLevel`, `SpacesCallable` enum
- `AMENAPP/Spaces/SpacesFeatureFlags.swift` — All Spaces feature flags (all default OFF in prod)
- `AMENAPP/Spaces/BereanSpaceMemberContract.swift` — `BereanSpaceInvokeRequest/Response`, `BereanSpaceMemberService`, trigger types, cited recall

### Design tokens (tokens only — no local color/material literals)
- `AMENAPP/AMENAPP/AmenTheme.swift` — `AmenTheme.Colors.*` semantic tokens
- `AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` — `AmenLiquidGlassPillButton`, `AmenLiquidGlassControlDock`, `AmenLiquidGlassBottomSheet`, `AmenLiquidGlassCapsuleSurface`
- **Token names to use**: `AmenTheme.Colors.amenGold`, `AmenTheme.Colors.amenBronze`, `AmenTheme.Colors.amenSilver`, `LiquidGlassTokens.blurThin` (= `Material.ultraThinMaterial`)
- For amenPurple/amenBlue: if not yet in `AmenTheme.swift`, Agent A adds them there (single source of truth)

### Berean AI
- Callable: `bereanChatProxy` (onCall) in `Backend/functions/src/bereanChatProxy.ts`
- SSE: `bereanChatProxyStream` (onRequest HTTP) in `Backend/functions/src/bereanChatProxyStream.ts` — returns `{"delta":"..."}`, `{"done":true}`, `{"error":"..."}`
- iOS client: `AMENAPP/AMENAPP/BereanGrokService.swift`
- Space-specific: `BereanSpaceMemberService.shared.invoke(...)` in `BereanSpaceMemberContract.swift`
- **Do NOT fork a new AI route. Reuse existing callables.**

### Stripe / Monetization
- In-App Giving: `AMENAPP/GivingInAppSheet.swift` (Apple Pay, 2% platform fee, PKPayment)
- Subscription: `AMENAPP/Subscription/AmenSubscriptionService.swift`
- Creator Checkout: `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantCheckoutService.swift`
- Fee math lives in the existing services — reuse identical numbers

### SCN Block model
- `ChurchNoteBlock` (Codable, Identifiable, Hashable) in `AMENAPP/ChurchNotes/ChurchNoteBlock.swift`
- Types: paragraph, quote, takeaway, prayer, action, reflection, scripture

### Hero-profile header style
- `PinnedProfileHeroSection` in `AMENAPP/AMENAPP/PinnedProfileHeroSurface.swift`
- Also: `AmenLivingHeroSystem.swift` for living hero variants

---

## Firestore schema (authoritative — new additions on top of SpacesCore)

```
communities/{id}
  name: String
  handle: String              // @handle, unique
  avatarURL: String?
  ownerUserId: String
  stripeConnectAccountId: String?
  createdAt: Timestamp
  members/{userId}
    role: "owner"|"admin"|"member"
    joinedAt: Timestamp
  links/{linkId}
    otherCommunityId: String
    status: "pending"|"active"|"revoked"
    scope: String             // e.g. "space/{spaceId}" or "community"
    createdBy: String         // userId
    createdAt: Timestamp
    updatedAt: Timestamp

spaces/{id}
  communityId: String         // owning community
  type: "chat"|"bibleStudy"|"group"|"announcement"
  title: String
  description: String?
  avatarURL: String?
  createdBy: String
  createdAt: Timestamp
  accessPolicy: "free"|"oneTime"|"recurring"
  priceConfig: { amountCents: Int, currency: String, interval: String? }?
  sharedWith: [String]        // denormalized communityIds — never join per frame
  // Soft-delete sentinel (matches SpacesCore):
  isDeleted: Bool             // default false; set true, never hard-delete
  members/{userId}
    role: String              // from AmenSpaceRoleType
    homeCommunityId: String?  // set for external members; nil = owning community
    access: "granted"|"none"
    joinedAt: Timestamp
  threads/{id}
    title: String
    createdBy: String
    createdAt: Timestamp
    lastMessageAt: Timestamp
    messages/{id}
      authorId: String
      body: String
      createdAt: Timestamp
      editedAt: Timestamp?
      reactions: { [emoji]: [userId] }
      attachments: [Attachment]
      isDeleted: Bool         // soft-delete only
  studies/{id}
    title: String
    passageRefs: [String]
    cadence: String?
    createdBy: String
    createdAt: Timestamp
    blocks/{id}               // reuse ChurchNoteBlock model exactly

// TOP-LEVEL — gated by single get(), never a tree walk
entitlements/{userId}_{spaceId}
  userId: String
  spaceId: String
  status: "active"|"grace"|"expired"
  source: "purchase"|"grant"
  stripeSubId: String?
  expiresAt: Timestamp?       // null = lifetime
  updatedAt: Timestamp
```

### Mapping to SpacesCore
- `AmenSpaceV2` remains the Swift model for existing Spaces fields
- Add new fields (`communityId`, `type`, `accessPolicy`, `priceConfig`, `sharedWith`) as an **extension** — do not replace `AmenSpaceV2`
- `SpacesCallable` enum lives in `SpacesCore.swift` — add new callables there (Agent A's job)

---

## Hard boundaries (never cross)

1. **Money never crosses a community Link in v1.** Owning community's Connect account collects. External members get comp/grant access only. Revenue-split is fast-follow.
2. **Never hard-delete data a view may render.** Status flips only. Soft-delete sentinel (`isDeleted`) everywhere. This prevents EXC_BAD_ACCESS / @MainActor / CALayerGetSuperlayer crashes.
3. **Entitlement is whole-Space, never per-artifact (v1).**
4. **Generic Community language only.** No "church" anywhere.
5. **Create-first / link-second.** No simultaneous co-creation in v1.
6. **One shared style file; tokens only.** `AmenTheme.Colors.*` and `LiquidGlassTokens.*`. No local color/material literals.
7. **Shared components live in Agent C's files and are imported — never re-implemented.**

---

## Liquid Glass design language

- `ultraThinMaterial` via `LiquidGlassTokens.blurThin`
- Glassmorphic cards: white overlay 0.08–0.20, stroke white 0.28–0.42, shadow 0.08 radius 18
- Spring motion: `Motion.liquidSpring` (bouncy spring, defined in AmenLiquidGlassComponents)
- Minimum chrome; AI assist where it removes a step
- Hero-profile header style for: Space detail, wizard confirm step, shared-community banner
- **Evident cross-community signal** (all three from Agent C — import, don't reimplement):
  - `LinkedGlyph` — interlocking-rings/chain in amenPurple over ultraThinMaterial, tappable
  - `SharedCommunityBanner` — glass pill ("Shared with [Community B]" / "N members are from [Community]")
  - `MemberRosterSheet` — external members SECTIONED under their `homeCommunityId`

---

## Agent file ownership (disjoint — no cross-agent file edits)

| Agent | New files | Touches existing |
|-------|-----------|------------------|
| A | `AMENAPP/Spaces/SpacesCommunityModels.swift`, `AMENAPP/Spaces/SpacesEntitlementModels.swift`, `firestore.rules` additions, `Backend/functions/src/spaces/` CFs | `SpacesCore.swift` (add callables + new types only) |
| B | `AMENAPP/Spaces/Chat/` directory (new) | `BereanSpaceMemberContract.swift` (read only) |
| C | `AMENAPP/Spaces/Shell/` directory (new), `AMENAPP/Spaces/SharedComponents/` directory (new) | `AmenLiquidGlassComponents.swift` (read only) |
| D | `AMENAPP/Spaces/Creation/` directory (new) | SCN block model (read only), BereanGrokService (read only) |
| E | `AMENAPP/Spaces/Monetization/` directory (new) | Giving/Subscription/Covenant (read only) |
| F | `AMENAPP/Spaces/Links/` directory (new) | C's SharedComponents (import only) |

---

## Space type → render mode (protocol-driven)

```swift
// type drives which body view is rendered — like Smart Church Notes block rendering
protocol SpaceBodyRendering {
    static var supportedType: SpaceType { get }
    func makeBody(space: AmenSpaceExtended) -> AnyView
}
// chat      → ThreadListView
// bibleStudy → StudyBlocksView  
// group     → GroupFeedView
// announcement → AnnouncementFeedView
```

---

## Smart creation wizard flow (Agent D)

1. **Intent** — Discussion / Study / Group
2. **Smart scaffold** — Berean via `bereanChatProxyStream` SSE; Study → passage ranges, cadence, prompts → maps to `studies` + `blocks`; Discussion/Group → starter prompts → seeds threads
3. **Access & pricing** — free/oneTime/recurring segmented control + live "~$X after fees" (reuse existing fee math)
4. **Confirm** — glass sheet, hero-profile header; on confirm: create `space` doc + scaffold + creator membership

---

## Run order

```
Agent A (alone) → merge → CONTRACT_A.md published
    ↓
Agents B, C, E (parallel) → CONTRACT_B.md, CONTRACT_C.md, CONTRACT_E.md
    ↓
Agents D (needs B+C) and F (needs C) → CONTRACT_D.md, CONTRACT_F.md
```

---

## Definition of done (all agents)

- Builds clean in `AMENAPP.xcworkspace` — 0 new errors, 0 new @MainActor warnings
- No hard-deletes of in-render data anywhere
- No parallel AI/fee/billing stacks introduced
- Tokens-only surfaces (no local color/material literals)
- All new components use `LiquidGlassTokens.blurThin` and `AmenTheme.Colors.*`
- `CONTRACT_x.md` published by each agent

---

## Fast-follow (do NOT build now)

- Simultaneous co-creation
- Cross-link revenue sharing
- Artifact-scoped entitlements
- Space-level moderation AI (Guardian) integration
- Ambient presence indicators
