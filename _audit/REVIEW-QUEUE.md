# REVIEW QUEUE — Overnight Audit 2026-05-30 / 2026-05-31

Items that were HIGH-risk, touched frozen contracts, or had confidence < 90%.
All client-side items are now RESOLVED. One backend action remains.

---

## ✅ RESOLVED — Client-Side Items

| # | Finding | Resolution |
|---|---------|-----------|
| RQ-02 | CF-03 — UNIMPLEMENTED error handling | Confirmed at all critical call sites: `bereanChatProxy` (ClaudeAPIService), `acceptAccessPass` (AmenAccessPassService), `createRealtimeSession` (BereanRealtimeSessionManager), `askAmenCompanion` (AskAmenCompanionRouter) |
| RQ-03 | AUTH-06 — Deactivation bypass | Client-side: Firestore field is fast-path; if deactivated, forces `getIDTokenResult(forcingRefresh: true)` and checks custom claim `deactivated` as authoritative. Backend claim setter is covered by RQ-01. |
| RQ-04 | AUTH-07 — COPPA age gate | Fixed `2026-05-31` (`63ec490`): `Calendar.dateComponents([.year])` check in `handleAuthentication()` before signup proceeds. |
| RQ-05 | SMART-01 — Hardcoded Amazon tag | Fixed `2026-05-31` (`b7da836`): Removed `"amenapp-20"` fallback; DEBUG asserts if key missing; release returns `nil` URL. |
| RQ-06 | SMART-02 — FTC affiliate disclosure | Already in place: `EnhancedLinkPreviewCard.swift:127-133` shows `AffiliateConfig.disclosure` when `isAffiliateLink` is true. |
| RQ-07 | STUDIO-09 — system_override bypass | Already fixed: `StudioWriteView.swift:800` sends `ai_mode` + `writing_type` enum values; `system_override` removed from payload entirely. |
| RQ-08 | STUDIO-04 — No cloud backup for drafts | Already implemented: `DraftSyncService.swift` uploads to `studioUserDrafts/{uid}/sessions/{sessionId}` on every auto-save (fire-and-forget, non-fatal). |
| RQ-09 | DS-A11 partial — VerseAttachmentViewModel | Already fixed in batch R24: uses `UIAccessibility.isReduceMotionEnabled` directly (correct pattern for ViewModels). |

---

## 🔴 OPEN — Requires Backend Action

### RQ-01 | HIGH | CF-01 — Two-codebase Backend architecture
**File:** `functions/index.js` (and all 378 iOS callers in Swift files)
**Status:** OPEN — iOS client is fully correct. Backend deploy required.

**Action required:**
1. Confirm `Backend/functions` TS codebase is deployed to Firebase project `amen-5e359`
   (`firebase deploy --only functions` from the Backend/functions repo)
2. When deployed, the `deactivated` custom claim setter (Auth-06 / RQ-03) also becomes active — no iOS change needed.
3. Long-term: consider consolidating both codebases into one repo.

**Why this can't be auto-fixed:** The 378 iOS callable invocations target functions that exist only in the Backend/TS codebase, not `functions/index.js`. This is a backend deployment issue, not a client-side issue.

---

---

## 🔴 OPEN — Additional Backend / Architecture Items

### RQ-13 | MEDIUM | DM field name mismatch
**File:** `MessagingImplementation.swift` + Firestore `conversations/{id}/messages` collection
**Status:** OPEN — client-side reads now tolerate both `timestamp` and `createdAt` fields, but historical Firestore documents still use the old name.
**Action required:** Run a Firestore migration script to copy `timestamp` → `createdAt` for all existing messages.

### RQ-17 | MEDIUM | PremiumManager — StoreKit 1 → StoreKit 2 migration
**File:** `AMENAPP/PremiumManager.swift`
**Status:** OPEN — still uses deprecated StoreKit 1 `SKProductsRequest`/`SKPaymentTransaction` APIs.
**Action required:** Migrate to StoreKit 2 (`Product.products(for:)`, `Transaction.updates`, `AppStore.sync()`). App Store Connect configuration unchanged.

---

*Updated: 2026-05-31 — all client-side items resolved; 3 backend items remain open*
