# REVIEW QUEUE — Overnight Audit 2026-05-30 / 2026-05-31

Items that are HIGH-risk, touch frozen contracts, or where confidence < 90%.
These require human decision before applying.

**RQ-09 RESOLVED** — `cb21f68` (VerseAttachmentViewModel — UIAccessibility guard applied)
**CF-03 PARTIAL** — `11a15f1` (bereanChatProxy, acceptAccessPass, createRealtimeSession error handling added; remaining 375 callers still unhandled)

---

## Remaining Items Requiring Human Decision

| # | Finding ID | Domain | Risk Level | File:Line | Description | Proposed Diff / Notes |
|---|-----------|--------|-----------|-----------|-------------|----------------------|

### RQ-01 | HIGH | CF-01 — Two-codebase Backend architecture
**File:** `functions/index.js` (and all 378 iOS callers in Swift files)
**Risk:** If the "Backend/functions TypeScript" codebase is not deployed to the Firebase project `amen-5e359`, all 378 iOS callable invocations fail silently or with unhandled errors at runtime. This is not fixable client-side — requires backend verification.
**Proposed action for human:** 
1. Confirm `Backend/functions` TS codebase is deployed to `amen-5e359` (`firebase deploy --only functions` from that repo).
2. Add the master function registry comment/doc linking both codebases.
3. Consider consolidating to one codebase long-term.
**NOT auto-fixed** — architecture decision, backend deploy required.

### RQ-02 | MEDIUM | CF-03 — Missing UNIMPLEMENTED error handling at critical iOS call sites
**Files:** `ClaudeAPIService.swift:115`, `AmenAccessPassService.swift:110,138`, `BereanRealtimeSessionManager.swift:37`, `AmenCompanionService.swift:18`, + 373 more
**Risk:** If Backend/TS functions are temporarily unavailable, iOS gets unhandled `FunctionsError` with no user-facing message.
**Proposed diff:** Add `.catch { error in if let e = error as? FunctionsErrorCode ... }` at each critical call site (AI proxy, access pass, realtime session). Safe to fix but scope is large — tagging for human prioritization.
**NOT auto-fixed** — scope too large for safe unattended run; needs prioritized human selection.

### RQ-03 | MEDIUM | AUTH-06 — Deactivation bypass on jailbroken devices
**File:** `AuthenticationViewModel.swift:337-381`
**Risk:** Client reads Firestore `isDeactivated` field before calling `getIDTokenResult(forcingRefresh:true)`. A patched client can return `false` and skip server-side claim check, bypassing account deactivation.
**Proposed fix:** Always call `getIDTokenResult(forcingRefresh:true)` on every auth state change; check custom claim `claims["deactivated"]` instead of Firestore field.
**NOT auto-fixed** — touches auth guard logic (frozen contract).

### RQ-04 | MEDIUM | AUTH-07 — COPPA age verification not enforced
**File:** `MinimalAuthenticationView.swift:776-781`
**Risk:** DOB collected during signup but no 13+ validation before `handleAuthentication()`. Users under 13 can complete signup.
**Proposed fix:** Validate `Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0 >= 13` before proceeding. Write validated DOB to `users/{uid}/userSecurity` so it can't be changed post-signup without re-verification.
**NOT auto-fixed** — COPPA compliance; needs legal/privacy review of implementation.

### RQ-05 | CRITICAL | SMART-01 — Hardcoded Amazon Associates tag
**File:** `AffiliateLinkBuilder.swift:19`
**Risk:** `"amenapp-20"` fallback value visible in decompiled binary. Tag cannot be rotated without app update.
**Proposed fix:** Remove fallback entirely — raise fatal error if `AMAZON_AFFILIATE_TAG` plist key missing (fails at build time, not silently in prod).
**NOT auto-fixed** — revenue/compliance impact; requires coordinated affiliate management review.

### RQ-06 | MEDIUM | SMART-02 — Incomplete affiliate disclosure in feed
**File:** `EnhancedLinkPreviewCard.swift`
**Risk:** FTC requires clear disclosure before user clicks affiliate links. Feed preview cards show no disclosure.
**Proposed fix:** Auto-populate `productDetails.safetyLabel` in stub generator; display it in `EnhancedLinkPreviewCard`.
**NOT auto-fixed** — FTC compliance; needs legal review of disclosure wording.

### RQ-07 | MEDIUM | STUDIO-09 — system_override safety bypass
**File:** `StudioWriteView.swift:800-853`
**Risk:** Client passes arbitrary `"system_override"` string to `studioGenerateContent` CF. If backend doesn't whitelist overrides, custom prompts could bypass GUARDIAN content policies.
**Proposed fix:** Remove `system_override` from client payload; pass an `aiMode` enum instead and let backend select system prompt from a server-side allowlist.
**NOT auto-fixed** — touches CF callable contract (frozen); backend change required.

### RQ-08 | MEDIUM | STUDIO-04 — No cloud backup for studio drafts
**File:** `StudioDraft.swift`, `StudioAICreationView.swift:292`
**Risk:** All drafts stored in SwiftData only — device reset or migration deletes all drafts.
**Proposed fix:** Create `DraftSyncService` that uploads drafts to `studioUserDrafts/{uid}/{draftId}` on Firestore on dismiss/background. Out of scope for unattended run (new feature, not a fix).
**NOT auto-fixed** — new Firestore collection + sync logic; needs design review.

### RQ-09 | LOW | DS-A11-partial — VerseAttachmentViewModel withAnimation in ViewModel
**File:** `VerseAttachmentViewModel.swift:282,297`
**Risk:** `withAnimation {}` calls in a `@MainActor` ViewModel — `@Environment(\.accessibilityReduceMotion)` not accessible from a ViewModel.
**Proposed fix:** Either (a) pass `reduceMotion: Bool` from the caller View, or (b) use `UIAccessibility.isReduceMotionEnabled` directly.
**NOT auto-fixed** — requires caller-side change; small scope but needs human decision on approach.

---

## P0/P1 Items Added — Context-Resume Session (2026-05-31 morning)

### RQ-10 | CRITICAL | Berean AI injection surface
**File:** `ClaudeService.swift`
**Risk:** `systemPromptSuffix` is entirely client-built and sent to the CF. A user can intercept and replace it to bypass guardrails or extract doctrinal prompt content.
**Proposed fix:** Move `systemPromptSuffix` construction to the `bereanChatProxy` CF; reject any client-supplied suffix field.
**NOT auto-fixed** — CF callable contract change.

### RQ-11 | CRITICAL | No crisis intercept in Berean `sendMessage()`
**File:** `BereanAIAssistantView.swift` / `BereanViewModel.sendMessage()`
**Risk:** Users expressing suicidal ideation, self-harm, or abuse receive no crisis resource card; Berean responds as a spiritual chatbot.
**Proposed fix:** Add client-side regex pre-scan (matching `AmenCrisisDetector` patterns) before submitting to proxy; inject a crisis resource banner if detected. CF-side intercept is the longer-term fix.
**NOT auto-fixed** — safety-critical; requires human-authored crisis copy + legal review.

### RQ-12 | P0 | Duplicate rows: UUID vs Firestore ID dedup mismatch
**File:** `OpenTableView.swift` / `FirebasePostService.swift`
**Risk:** Feed dedup key is `post.id` which may be a locally-generated UUID on optimistic inserts, then replaced by Firestore document ID on confirmation — same post appears twice.
**Proposed fix:** Generate the Firestore doc ID client-side before write (`db.collection("posts").document()`) so the ID is stable end-to-end. Verify all optimistic-insert paths.
**NOT auto-fixed** — requires tracing the full optimistic-insert flow before changing ID assignment.

### RQ-13 | P0 | DM field name mismatch — messages silently lost
**File:** `FirebaseMessagingService.swift`
**Risk:** Listener orders by `"timestamp"` but `sendMessage()` writes `"createdAt"`. New messages land outside the listener's sort window and never appear without a manual refresh.
**Proposed fix:** Standardize on `"createdAt"` everywhere; migrate the listener query; run a one-time Firestore migration to backfill `"createdAt"` on existing docs.
**NOT auto-fixed** — data migration required; risk of breaking existing DM threads.

### RQ-14 | P0 | `ImageModerationService.moderateImage()` stub
**File:** `ImageModerationService.swift`
**Risk:** All image uploads bypass moderation. CSAM, graphic violence, and hate imagery pass through unchecked.
**Proposed fix:** Wire to the `moderateImageContent` CF callable (backend exists). Gate upload confirmation on moderation approval.
**NOT auto-fixed** — CF integration + UX for rejection state needed; content safety critical path.

### RQ-15 | P0 | Apple/Google Sign-In bypasses COPPA age-gate
**File:** `AuthenticationViewModel.swift`
**Risk:** Social sign-in goes directly to account creation without `AgeGateView`. Under-13 users created via social login have no age verification.
**Proposed fix:** After social credential resolution, redirect new social users to `AgeGateView` before completing account setup; persist verified DOB to `users/{uid}/userSecurity`.
**NOT auto-fixed** — COPPA compliance; requires legal review.

### RQ-16 | P1 | Anonymous prayer `authorId` plaintext
**File:** `PrayerView.swift`
**Risk:** "Anonymous" prayers still write `authorId = Auth.currentUser.uid`. Anyone with read access can link the prayer to the user.
**Proposed fix:** Omit `authorId` field for anonymous prayers; use a CF to enforce ownership via request document + token, not authorId.
**NOT auto-fixed** — privacy impact; Firestore rule changes needed.

### RQ-17 | P1 | `PremiumManager.hasProAccess` in UserDefaults
**File:** `PremiumManager.swift`
**Risk:** Jailbroken devices can set `hasProAccess = true` without a valid purchase.
**Proposed fix:** Verify entitlement server-side via StoreKit2 `Transaction.currentEntitlements` + CF verification on each gated feature. Do not use UserDefaults as sole source of truth.
**NOT auto-fixed** — StoreKit2 migration required; revenue impact.

<!-- Populated by Phase 1 & 2 -->
