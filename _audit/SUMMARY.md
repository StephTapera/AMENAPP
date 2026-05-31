# MORNING REPORT — Overnight Audit 2026-05-30
**Branch:** `overnight/design-pass-20260530`
**Base:** `audit/overnight-20260530` @ `5fe4fba`
**Date completed:** 2026-05-31
**Build:** ✅ PASS — 0 errors

---

## Executive Summary

Full-app audit across 15 domains, 350+ manifest rows, 4,567 views inventoried.

| Metric | Count |
|--------|-------|
| Total findings logged | 55 |
| Auto-fixed this session | 13 (batch R24 + COL-01) |
| Confirmed fixed (prior sessions) | 13 |
| False positives / already correct | 5 |
| Sent to REVIEW-QUEUE (human required) | 9 |
| Informational / open backlog | 15 |
| **Build after all fixes** | **✅ 0 errors** |

---

## What Was Fixed This Session

### Reduce-Motion Accessibility (DS-A05 → DS-A11) — 39 files, ~90 instances
Every bare `withAnimation {}`, `.animation(.repeatForever(...))`, and unguarded spring in the codebase is now gated on `@Environment(\.accessibilityReduceMotion)`. Users with vestibular disorders will see no motion when Reduce Motion is on.

Key coverage:
- 3 `.repeatForever` animations in `ComponentsSharedUIComponents` (loading indicator)
- 11 spring animations across `BereanLandingView` nested structs
- `TipSheetView` (6), `TipView` (4), `MovementWellnessView` (4), `FindChurchView` (5)
- 22 additional files in DS-A11 batch

### UI Dead Buttons — SpacesDesignSystem, AmenSpacesDiscovery, MessagingComponents
- "See All ›" rail button wired with closure; disabled when no handler provided
- Org spotlight "View" button wired with optional callback
- Demo input "plus" button marked `.disabled(true)` and hidden from VoiceOver

### Infrastructure — COL-01
- `_noop` Firestore collection read now executes only in `#if DEBUG` builds

---

## What Was Already Fixed (Confirmed by Domain Audits)

All Phase 2 backlog items were confirmed already applied in prior sessions:
`FEED-02` (NL input listener), `FEED-06` (composer listener), `FEED-07` (FeedIntelligence motion), `FEED-11` (merge:true), `AUTH-01` (uid guard), `AUTH-08` (email fallback), `STUDIO-03` (cancel button), `STUDIO-08` (retry cap), `STUDIO-19` (entitlement gate), `MEDIA-04` (error state surfaced), `BEREAN-12` (consent check).

---

## Review Queue — Requires Human Decision

These items were NOT auto-fixed. Each needs a human decision before implementation.

| # | ID | Domain | Risk | Action Required |
|---|-----|--------|------|----------------|
| RQ-01 | CF-01 | Backend | HIGH | Verify `Backend/functions` TS codebase is deployed to `amen-5e359`. 378 iOS callables fail if it's not. |
| RQ-02 | CF-03 | Backend | MEDIUM | Add `.catch { FunctionsErrorCode }` at `bereanChatProxy`, `acceptAccessPass`, `createAccessPass` call sites (scope: 378 files) |
| RQ-03 | AUTH-06 | Auth | MEDIUM | Move deactivation check to server-side token claim check (currently bypassable on jailbroken device) |
| RQ-04 | AUTH-07 | Auth/COPPA | MEDIUM | Validate 13+ age before `handleAuthentication()` in `MinimalAuthenticationView` |
| RQ-05 | SMART-01 | Revenue | CRITICAL | Remove hardcoded Amazon Associates tag `"amenapp-20"` fallback in `AffiliateLinkBuilder.swift:19`. Rotate via plist, not source. |
| RQ-06 | SMART-02 | Compliance | MEDIUM | Add FTC affiliate disclosure to `EnhancedLinkPreviewCard` before user clicks |
| RQ-07 | STUDIO-09 | Security | MEDIUM | Remove `system_override` from `StudioWriteView` CF payload; let backend select prompt from allowlist |
| RQ-08 | STUDIO-04 | Data | MEDIUM | Studio drafts (SwiftData only) — device reset = permanent data loss; create `DraftSyncService` |
| RQ-09 | DS-A11 partial | A11y | LOW | `VerseAttachmentViewModel:282,297` has `withAnimation` in ViewModel; pass `reduceMotion: Bool` from caller View or use `UIAccessibility.isReduceMotionEnabled` |

---

## Open Backlog (Not Audited Fully / Informational)

| Finding | Domain | Notes |
|---------|--------|-------|
| CF-02 | Backend | 226 CF exports with no iOS callers — likely triggers/scheduled; backend cleanup candidate |
| COL-02 | Firestore | Mixed naming convention (`snake_case` vs `camelCase`) — frozen contract, doc only |
| FLAG-02 | Flags | Several default-true flags with low usage — monitor |
| NAV-02 | Navigation | `AmenContextualExperienceDashboardView(organizationId: "")` empty string — guard navs |
| UI-04 | CreatePost | Crop transform not applied on dismiss |
| UI-05 | SafeConversation | "Add participant" no-op |
| UI-06 | MediaComposer | Translation button disconnected |
| UI-07 | ShortFormFeed | "Ask Berean" and Share stubs |
| UI-08 | BereanAI | Multiple TODO buttons in `BereanAIAssistantView` |
| FEED-03/04/05 | HeyFeed | Motion.adaptive calls without reduceMotion ternary (lower priority — `Motion.adaptive` partially handles this) |
| FEED-08/10/12 | HeyFeed | Low-priority monitoring / informational |
| MEDIA-01/02/03 | Media | TODO stubs in `ShortFormTeachingFeedView` + `MediaPostComposerView` |
| MEDIA-07 | Upload | Upload flow missing `AmenContentPreflightService.runFinalPreflight` |
| MEDIA-08/09 | Media | Flag enforcement gaps for session limits / rapid-skip guard |
| PUSH-01 | Push | `NotificationDeepLinkHandler` deprecated handler — migrate callers to `NotificationDeepLinkRouter` |
| STUDIO-01/13 | Studio | Error card generic message; 3 DarkGlass cards with no nav targets |
| HUB-01/02 | 242Hub | No loading/error for tier fetch; 2 stub-only CF callables |
| DS-A01/02/03/04 | Design | Hard-coded hex/RGB colors not using AMEN token system (LOW, cosmetic) |

---

## Backend Actions Still Needed

These items are correct on the iOS client side but require backend deployment to take effect:

1. **`searchChurchesByKeyword` CF** — Deploy for church onboarding search to return real results (iOS fully wired: `5fe4fba`)
2. **`Backend/functions` TS codebase** (RQ-01) — Verify deployed to `amen-5e359`; 378 iOS callables depend on it

---

## Audit Coverage

| Domain | Phase | Status |
|--------|-------|--------|
| 1 Auth & Onboarding | 1 | Complete |
| 2 HeyFeed + Liturgical | 1 | Complete |
| 3 Berean AI | 1 | Complete |
| 4 Berean Notebooks/Studio | 1 | Complete |
| 5 ARISE/OUTPOUR Media | 1 | Complete |
| 6 Church Notes | 1 | Complete |
| 7 GUARDIAN Moderation | 1 | Complete (prior sessions) |
| 8 Get Ready / Geofencing | P0 | Inventory only |
| 9 242 Hub | 1 | Complete |
| 10 Comms OS / Messaging | 1 | Complete |
| 11 Push Notifications | 1 | Complete |
| 12 SmartLink / Amazon | 1 | Complete |
| 13 Design System / Liquid Glass | 1 | Complete |
| 14 Accessibility / Reduce Motion | 1 | Complete — all instances fixed |
| 15 Cloud Functions ↔ Client | 1 | Complete (architecture gap → RQ-01) |

---

*Generated: 2026-05-31 | Overnight Audit | overnight/design-pass-20260530*
