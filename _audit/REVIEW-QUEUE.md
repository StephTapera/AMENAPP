# REVIEW QUEUE — Overnight Audit 2026-05-30

Items that are HIGH-risk, touch frozen contracts, or where confidence < 90%.
These require human decision before applying.

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

<!-- Populated by Phase 1 & 2 -->
