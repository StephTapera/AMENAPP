# LiquidReplyPreviewRotation — QA Report
**Feature:** Dynamic Reply Preview Rotation on PostCard (`LiquidReplyPreviewRotator`)
**Contract version:** 1.0.2
**Branch:** `audit/2026-05-21` (fixes layered on top)
**QA date:** 2026-05-27
**Verdict:** ✅ SHIP (with one mandatory pre-ship step)

---

## Build Gate

| Run | Command | Result |
|-----|---------|--------|
| Clean | `xcodebuild clean` | CLEAN SUCCEEDED |
| Build | `xcodebuild … IPHONEOS_DEPLOYMENT_TARGET=26.2` | **BUILD SUCCEEDED** |

No compiler errors. One pre-existing build warning (run script phase with no declared outputs — not introduced by this feature).

The `DiscoverModels.stringsdata` duplicate conflict seen on the first build attempt was a stale DerivedData artifact. Clean + rebuild resolved it. No code change was required.

---

## Gap Register Verdict (21 items)

| # | Item | Status |
|---|------|--------|
| G-01 to G-18 | All pre-existing components | PRESENT (verified in recon) |
| G-19 | Firestore `dynamicReplyPreviews` security rules | **CLOSED** |
| G-20 | Composite index `posts: previewDirty + previewExpiresAt` | **CLOSED** |
| G-21 | Flag default → `true` for exercisability | **CLOSED** |

Zero open gaps at ship.

---

## STEP 1 — Contract + Recon

- CONTRACT.md version bumped 1.0.1 → 1.0.2.
- Full gap register written (Section 21) with 21 line items.
- Stale "NOT FOUND" status for `openReplies`/`showReplyActions` corrected — both exist at `AmenContentRouter.swift:144` and `:199`.

---

## STEP 2 — Gap Closures

### G-19: Firestore Security Rules

**File**: `firestore.rules`
**Change**: Added `match /posts/{postId}/dynamicReplyPreviews/{previewId}` block after the `audit` subcollection block (line ~5234).

```
allow read: if isSignedIn() && post is not removed
allow write: if false  // Cloud Functions only
```

**Rationale**: Without this rule, Firestore's default deny would block the iOS client from reading the `dynamicReplyPreviews` subcollection entirely, making the chip never appear even when previews are ready.

### G-20: Composite Index

**File**: `firestore.indexes.json`
**Change**: Added two entries:
1. `posts` collection: `previewDirty ASC + previewExpiresAt ASC` — required by `rebuildReplyPreviews` query (`where previewDirty == true, orderBy previewExpiresAt`)
2. `dynamicReplyPreviews` collection group: `safetyState ASC + expiresAt ASC` — supports future admin tooling for finding stale/unsafe previews without a full collection scan

**Rationale**: Without the `posts` index, the Cloud Function's rebuild query would fail in production with "index required" error, causing `rebuildReplyPreviews` to never persist results.

### G-21: Flag Default

**File**: `AMENAPP/AMENFeatureFlags.swift:394`
**Change**: `replyPreviewRotationEnabled: Bool = false` → `replyPreviewRotationEnabled: Bool = true // FLIP TO false BEFORE SHIPPING`

**Rationale**: Per user directive — feature flag ON so the full chip-to-sheet flow is exercisable in the simulator/TestFlight build. Remote Config can override to `false` in production.

---

## STEP 3 — Integration Verification

PostCard seam confirmed at `PostCard.swift:3897`:

```
inlineObjectHubSection
safetyOSReactionSection

dynamicReplyPreviewSection   ← CORRECT position

postInteractionSection
```

Full wiring verified:
- `resolvedPreview` computed property at line 3229 guards flag + filters `isSafe && !isExpired` candidates
- `LiquidReplyPreviewRotator` receives `candidates` from `post.dynamicReplyPreviewCandidates`
- `onOpenReplies` → `AmenUniversalContentRouter.shared.openReplies(postId:highlightedReplyId:)` ✅
- `onLongPress` → `AmenUniversalContentRouter.shared.showReplyActions(postId:replyId:)` ✅
- `.sheet(item: $localReplyActionsTarget)` → `ReplyActionsMenuView` with 5 real actions ✅
- `.onReceive($replyActionsTarget)` guards on `target.postId == post.firestoreId` ✅
- `.id(resolvedPreview?.generatedAt)` drives crossfade on server rotation ✅
- `.frame(height: 44)` prevents feed scroll jump on chip appear/disappear ✅

Analytics tracking:
- `replyPreviewShown` — exists at `AMENAnalyticsService.swift:114` ✅
- `replyPreviewTapped` — exists at `AMENAnalyticsService.swift:115` ✅
- `replyPreviewType` — exists at `AMENAnalyticsService.swift:116` ✅

---

## STEP 4 — Test Coverage

Backend unit tests present: `Backend/functions/src/generateDynamicReplyPreviews.test.ts`
Covers: `selectFollowedReplyFromRelationships`, `hasStrongRelationship`, `detectCommunityPulse`, resolver ladder, composite scoring formula.

No new Swift unit tests introduced (the chip and rotator are pure display components; business logic lives in the Cloud Function and is covered by the backend test file).

---

## Pre-Ship Checklist

| Item | Owner | Status |
|------|-------|--------|
| Flip `replyPreviewRotationEnabled` default back to `false` in `AMENFeatureFlags.swift:394` | Engineering | **REQUIRED before merge to main** |
| Deploy `firestore.rules` (contains new `dynamicReplyPreviews` rule) | Infra | Required before feature goes live |
| Deploy `firestore.indexes.json` (contains new `posts` composite index) | Infra | Required — index build takes ~minutes in production |
| Set `reply_preview_rotation_enabled = true` in Firebase Remote Config when ready to enable for users | Product | Controls rollout |
| Re-apply Firebase FoundationModels DerivedData patch after any `swift package update` | Engineering | See FIX_LOG.md BUILD-001 |
| Revert iOS Deployment Target from 17.0 → 26.2 in Xcode Build Settings | Engineering | See FIX_LOG.md DEP-001 |

---

## Known Non-Issues

- `AMENWidgetExtensionExtension` crashes with `EXC_GUARD / GUARD_TYPE_USER` repeatedly — pre-existing, not caused by this feature. See FIX_LOG.md WIDGET-001.
- Run script build phase warning ("does not specify any outputs") — pre-existing, not introduced by this feature.
- `DiscoverModels.stringsdata` build conflict on first cold build after clean — resolved by clean + rebuild. Root cause: stale DerivedData artifact. Not caused by any source change in this session.

---

*QA Report written by orchestrator — 2026-05-27*
