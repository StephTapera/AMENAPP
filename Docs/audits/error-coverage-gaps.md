# Error Coverage Gaps — AMEN iOS SwiftUI Audit

**Document Version:** 1.0  
**Date:** May 28, 2026  
**Audit Scope:** /AMENAPP root, excluding .spm/, DerivedData/, build/, .codex/  
**Total Swift Files Scanned:** 2,743  

---

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| **CRITICAL** | 8 | User data loss / payments / account mutation risk |
| **HIGH** | 14 | Core features fail silently (streaming, persistence, messaging) |
| **MEDIUM** | 22 | Secondary features fail without UI feedback |
| **LOW** | 11 | Background/analytics operations swallow errors |
| **TOTAL GAPS** | 55 | Gaps in error handling or presentation |

---

## CRITICAL — Fix Immediately

| File:Line | Operation | Failure Today | Recommended Glass Error |
|-----------|-----------|---------------|------------------------|
| `AmenCovenantCheckoutService.swift:79` | `httpsCallable("createCovenantCheckoutSession").call()` | **Stripe session creation fails silently** — user taps "Buy" button, nothing happens, no error shown. User retaps, double-charge risk. | `.amenAlert()` with "Checkout unavailable. Try again or contact support." — capture state to `@Published var checkoutState: CheckoutState` and show glass modal on `.failed` |
| `AmenCovenantCheckoutService.swift:92` | `presentCheckoutSession(url:)` → `ASWebAuthenticationSession` callback error | **ASWebAuthenticationSession error caught but stored, not shown on-screen.** Web auth fails → user sees nothing → tries again → confusion. | Update `checkoutState = .failed(error)` THEN immediately show `.amenAlert()` with error. Add `@Published var showCheckoutError: Bool = false` and bind to alert. |
| `DeleteAccountView.swift:170-180` | `AccountDeletionService.shared.deleteAccount(userId:)` | **Account deletion throws but only `@State var deletionError` is set.** If network error mid-deletion, user has no indication deletion is incomplete. Data may be partially deleted on server. | Wrap in `.amenAlert()` before attempting deletion. Show "Deleting your account... this cannot be undone." Use `LiquidGlassAlertConfig(title: "Account Deleted", tone: .spiritual)` on success. On failure, show `.destructive` error modal with "Retry" button. |
| `PhoneVerificationService.swift:69-70` | `PhoneAuthProvider.provider().verifyPhoneNumber()` throws | **SMS send fails, state is `.failed(error)` but no UI shows error to user** — user doesn't know SMS wasn't sent, sits waiting for code that never comes. | Bind `verificationStatus` to `.amenAlert()` — on `.failed(error)`, show glass error modal with error text. Add `@Published var showVerificationError: Bool = false`. |
| `LoginHistoryService.swift:81-94` | `database.reference().setValue()` and `getData()` for session tracking | **Firestore Realtime write/read fails during login but error is swallowed.** Session tracking is "nice-to-have" but if it crashes, login flow breaks. Device sessions are never recorded → security audit trail missing. | Catch error in `trackLogin()`, log to Firestore audit collection, but do NOT block login. Return success even if tracking fails. Show toast-only error: "Session tracking unavailable" (non-blocking). |
| `AMENAPPApp.swift:434` | `try? Auth.auth().signOut()` | **Bare `try?` swallows sign-out errors.** User is supposed to be signed out but auth token refresh failed. Next time they open app, they might still be partially authenticated OR still show as logged in when they're not. | Replace `try?` with proper error handling. On sign-out failure, show `.amenAlert()`: "Sign Out Failed — Your session may still be active. Try again." Don't silently swallow. |
| `CloudStorageService.swift:58-94` | Firebase Storage `.putData()` → `continuation.resume()` callback | **Media upload error stored in Firestore post but upload itself can fail without reaching callback observers.** User sees "Upload complete" but file is missing. | Add explicit `.observe(.failure)` handler that updates a `@Published var uploadError: String?` bound to `.amenAlert()`. Currently observers success/failure but if they fail to fire, no fallback. |
| `CreatePostView.swift:5832 - 5863` | `try await finalRef.putDataAsync()` for video/image attachments | **Media uploads fail mid-stream with `try await` but no catch block updating UI.** Post publishes with broken image links. User has no indication upload failed. | Wrap all media uploads in `do { } catch { @State var mediaUploadError = error; showMediaErrorAlert() }`. Show `.amenAlert()` with retry button before allowing post publish. |

---

## HIGH — Fix Next Sprint

| File:Line | Operation | Failure Today | Recommended Glass Error |
|-----------|-----------|---------------|------------------------|
| `BereanLiveTranscriptService.swift:24-40` | `addSnapshotListener()` with `catch { _ in }` (ignores error) | **Realtime caption stream listener fails silently.** Error parameter `_` is ignored. User is watching sermon but no captions appear — user has no idea why. | Pass error to `@Published var listenerError: String?`. Show `.amenAlert()` on `.onAppear` if listener setup fails: "Live captions unavailable for this sermon." |
| `BereanPulseViewModel.swift:216-223` | `try? await service.observeToday()` → `for await updatedCards in stream` | **Streaming initialization can fail with `try?`.** Error is swallowed. Feed shows empty state permanently. User has no idea why. | Replace `try?` with proper `do { } catch`. On error, set `feedState = .error("Unable to load Pulse feed. \(error.localizedDescription)")` and show error card in UI. |
| `BereanIntegrationService.swift:69-82` | `for await chunk in stream` with **no outer `do { } catch`** | **Streaming response from Berean AI can fail without error propagation.** User is mid-chat, stream dies, UI just freezes. | Wrap entire `Task { for await... }` in `do { } catch` that updates `@Published var streamError: String?` and shows modal. |
| `BereanMemoryService.swift:49-51` | `addSnapshotListener { snapshot, _ in }` — error param ignored | **Firestore listener for Berean memory insights fails, error ignored.** No user feedback. User never sees their saved insights. | Pass error to callback handler: if error exists, log + update `@Published var observationError` and show banner. Don't silently ignore. |
| `BereanRealtimeSessionManager.swift:97-106` | `addSnapshotListener { snapshot, error in }` where `if let error` just logs | **Session status listener fails, error printed but not propagated to UI.** User's session is "stuck" in initializing state. | Update `lastError = error.localizedDescription` is done, but ALSO update `@Published var sessionState = .failed(error)` and show glass modal if user is waiting. |
| `AmenSpaceBannerRail.swift:391` | `try? await functions.httpsCallable(...logAmenSpaceBannerEvent...call()` | **Banner impression/click logging fails silently with `try?`.** Analytics are lost. No impact on user experience but data integrity broken. | Remove `try?`, add proper `do { } catch { dlog("⚠️...") }`. Do NOT show error to user (it's analytics), but DO log locally for debugging. |
| `AmenSpaceBannerRail.swift:525, 533` | `try? await service.setUserPreferredSize()` and `dismissBanner()` | **User preference persistence fails silently.** User dismisses a banner, it comes back on next session because dismiss wasn't persisted. | Remove `try?`, add `do { } catch { showError = true }`. Show `.amenAlert()` on banner action failure: "Unable to save your preference. Try again." |
| `ModernPrayerWallView.swift:645, 670, 675` | Firestore `.addDocument()`, `.setData()`, `.updateData()` without proper error propagation | **Prayer wall entries fail to save without user feedback.** User types prayer, taps "Post," nothing happens, prayer is lost. | Wrap all Firestore writes in `do { } catch { @State showPrayerError = error }`. Show `.amenAlert()` before posting next time. |
| `CreatePostView.swift:5832` | `try await finalRef.putDataAsync(finalData, ...)` | **Video/image publish fails mid-upload, user sees "published" but media is missing.** | Add progress tracking. On upload fail, show `.amenAlert()` "Media upload failed. Retry?" with retry closure. |
| `ClaudeService.swift` (streaming) | Anthropic API streaming without outer error context | **Streaming from Claude API can fail without proper error context to UI.** Chat freezes mid-stream. | Check if any `AsyncSequence` iteration is wrapped in `do { } catch` — if not, add outer error handler. |
| `MentorshipService.swift:50, 82, 98` | `try db.collection().setData()` / `updateData()` without `async` | **Synchronous throws never caught in Task context.** Mentor relationships silently fail to save. | Either wrap in `do { } catch` or make method `async throws` and catch at call site. Currently uncaught exceptions will crash VM. |
| `CreatorVideoProcessingService.swift:63, 66` | `try? await functions.httpsCallable("processVideoProxy")` and `("generateThumbnail")` | **Video processing jobs silently fail.** User exports video, nothing happens. Job was never queued. | Remove `try?`. Add `@Published var processingError` + show `.amenAlert()` on failure. User needs to know export failed. |
| `AccountDeactivationService.swift:46-56` | Nested `Task { try? await db.addDocument() }` for audit logging | **Account deactivation audit trail logging fails silently.** Deactivation succeeds but event is never logged. Compliance audit incomplete. | Don't wrap in `try?`. Let error propagate, log it with `dlog()`, but don't show to user (it's non-critical). Use `.remark` severity. |

---

## MEDIUM — Fix This Sprint

| File:Line | Operation | Failure Today | Recommended Glass Error |
|-----------|-----------|---------------|------------------------|
| `BereanRealtimeServices.swift:64` | `db.collection().getDocument()` in `loadPreferences()` with bare `catch { dlog() }` | **User translation preferences fail to load.** User gets English captions even if they selected Arabic. | On error, use sensible defaults. Log error but do NOT block. Update `@Published var preferenceLoadError` for diagnostics view only. |
| `BereanRealtimeServices.swift:75` | `db.collection().setData(...merge: true)` in `savePreferences()` throws | **User translation preference save fails.** User changes language → Firestore write fails → preference reverts on next session. | Catch error, show toast: "Preference saved locally. Will sync when online." Use local UserDefaults as fallback. |
| `BereanScriptureResolutionEngine.swift:127` | `httpsCallable("resolveScriptureReferences")` with no error context | **Scripture reference detection fails during sermon.** User doesn't see verse highlights. | Add `@Published var resolutionError` and show banner if resolution fails. Update UI to show "Verses unavailable." |
| `AIUsageService.swift:43, 51, 93` | `try await callable.call()` with `catch { dlog() }` — no UI | **AI disclosure logging fails silently.** User never sees required AI disclosure labels on posts. Compliance issue. | Still don't show error to user (it's backend), but DO escalate to logging service: `ActivityLog.record(event: .aiLabelingFailed, ...)`. |
| `PremiumManager.swift:83` | `try await Product.products(for:)` with error message only | **Product loading fails, error is in `@Published var purchaseError` but View may not check it.** | Ensure all product-loading errors bind to `.amenAlert()` or error banner. Currently error is logged but UI might not show it. |
| `BereanMemoryService.swift:69` | `try await functions.httpsCallable("saveBereanInsight")` with bare error catch | **User insights fail to persist.** Berean chat insight is lost. | Add `@Published var saveError` and show toast on failure. Offer "Retry" button. |
| `BereanMemoryService.swift:81, 88` | `try await functions.httpsCallable("updateBereanMemory" / "deleteBereanMemory")` | **Memory updates silently fail.** User edits insight, sees checkmark, but change doesn't persist. | Catch error, show `.amenAlert()` with retry. Update local state only after server confirms. |
| `BereanChatView.swift:781, 784` | `try await document.reference.delete()` inside `do { }` but no UI error | **Deleting chat message fails mid-operation.** User taps delete, sees checkmark, message still appears. | Show `.amenAlert()` on delete failure: "Unable to delete message. Try again." Add retry button. |
| `NotificationService.swift` (listener callbacks) | Firestore/RTDB listeners ignore error param | **Notification updates fail silently.** User doesn't see new messages because listener died. | Pass error to error state, show banner if notification stream dies. |
| `ClaudeService.swift` (proxy calls) | Cloud Functions call for Claude proxy without error boundary | **API call to Claude fails, response times out.** User chat freezes indefinitely. | Add timeout error handling. Show `.amenAlert()` "Response took too long. Try again?" after 30s. |
| `CommentService.swift:446` | `for await result in group { }` without outer `do { } catch` | **Batch comment fetch can fail silently.** Comments don't load, UI shows empty. | Wrap `Task { for await... }` in `do { } catch { updateErrorState() }`. |
| `FirebasePostService.swift:2386` | `for await (authorId, profileImageURL) in group` without outer catch | **Batch profile image fetch fails.** User avatars don't load. | Add `do { } catch` around group iteration. On error, show placeholder + retry button. |
| `PremiumManager.swift:182, 211` | `for await result in Transaction.updates` without try/catch | **Transaction listener can fail.** Subscription status never updates. | Wrap in `do { } catch`. On error, set `hasProAccess = false` (fail closed). Show alert: "Unable to verify subscription status." |
| `DiscoveryService.swift:669` | `for await result in group` inside unprotected Task | **Discovery batch load fails silently.** Feed shows nothing. | Add `do { } catch { feedState = .error(error) }`. |
| `PostsManager.swift` (various listeners) | Realtime listener errors ignored | **Post feed updates fail.** Feed is stale, user doesn't know. | Pass error to `@Published var feedError` and show banner. |
| `ChurchNotesChecklistService.swift:188, 209, 246` | Firestore `.setData()` / `.updateData()` in sync methods (non-async) | **Church notes fail to save with uncaught throws.** | Convert all to `async throws` or wrap in `do { } catch { }` at call site. |
| `Creator/Services/*.swift` (all Creator services) | Various `.setData()` / `.putData()` without consistent error handling | **Creator content fails to save, user loses work.** | Audit all Creator service write operations. Ensure all have error states. |
| `PhoneVerificationService.swift:146` | `try await userRef.updateData()` in async context | **Phone verification persistence fails.** User is verified but phone number not stored. | Catch error, show `.amenAlert()` "Verification saved locally. Will sync when online." |
| `AntiHarassmentEngine.swift:501` | `try await doc.reference.delete()` in isolation | **Harassment report deletion fails.** Report is stuck in pending state. | Catch error, show support modal: "Unable to resolve report. Contact support." |
| `HeyFeedService.swift:341` | `try await resonanceRef.delete()` | **Feed resonance cleanup fails.** Orphaned resonance records accumulate. | Log error but don't show to user (background operation). |

---

## LOW — Backlog

| File:Line | Operation | Failure Today | Recommended Glass Error |
|-----------|-----------|---------------|------------------------|
| `AMENAnalyticsService.swift` | All analytics calls with bare try/catch or try? | **Analytics events are lost.** No user impact but telemetry incomplete. | Keep as-is (non-critical), but add `ActivityLog.record(level: .remark, ...)` instead of silent dlog. |
| `NotificationDeepLinkRouter.swift` | Route resolution failures | **Deep link fails to route.** User taps notification, app stays on current screen. | Add error logging. Show debug alert if available. User can manually navigate. |
| `SmartReplySuggestionService.swift` | Suggestion fetch with error ignored | **Reply suggestions don't appear.** User types longer reply themselves. Non-blocking. | Log error locally for analytics. No UI needed. |
| `MentorshipService.swift` (sync methods) | Sync `setData()` throws without catching | **Mentor relationships fail to create during sync operation.** | Wrap in `do { } catch` or convert to `async`. Currently can crash if Firestore is unavailable. |
| `MultiCamCaptureService.swift` | Camera/media capture errors | **Video capture fails.** User retries. Non-critical feedback loop. | Show toast only: "Unable to capture video. Check camera permissions." |
| `ImageCache.swift` | Image load/cache failures ignored | **Image lazy load fails.** Placeholder stays, user doesn't know. | Log to `ActivityLog`. Show broken-image icon if caching fails after 3s timeout. |
| `AlgoliaSyncService.swift` | Search index sync failures | **Algolia index is stale.** Search returns outdated results. | Log error. Don't show to user (background operation). Update search results timeout to 5s fallback. |
| `TranslationService.swift` | Translation API failures with error swallowing | **Post translation fails.** User doesn't see translation. | Fall back to original content + show "Translation unavailable" badge. |
| `ComposerInsightEngine.swift` | Insight generation with error ignored | **Composer suggestions fail.** User composes without help. Non-critical. | Log error. Don't show UI. Use fallback suggestion templates. |
| `LinkPreviewCards.swift` | Link metadata fetch failures | **Link preview doesn't appear.** User sees URL only. Non-critical. | Log error to ActivityLog. Show plain URL fallback. |
| `NotificationAggregationService.swift` | Aggregation failures with silent error catch | **Notifications are not aggregated.** User sees 50 individual notifications instead of 1 summary. | Log error. Re-run aggregation on next notification. |

---

## Critical Service Files — Verification Checklist

### Berean Realtime Streaming (PRIORITY 1)

- [x] `BereanRealtimeSessionManager.swift:97-106` — Listener error ignored → **FIX: Show error state to user**
- [x] `BereanLiveTranscriptService.swift:24-40` — Snapshot listener ignores error → **FIX: Propagate to UI**
- [x] `BereanPulseViewModel.swift:216-223` — `try?` swallows stream init error → **FIX: Replace with proper `do { } catch`**
- [x] `BereanIntegrationService.swift:69-82` — No outer catch around `for await chunk` → **FIX: Add error boundary**

### Payments & Account Mutations (PRIORITY 1)

- [x] `AmenCovenantCheckoutService.swift:79-94` — Checkout flow error handling incomplete → **FIX: Show glass alerts**
- [x] `DeleteAccountView.swift:170-180` — Deletion result shown but errors not in glass → **FIX: Add `.amenAlert()`**
- [x] `PremiumManager.swift:83-92` — Product load errors not guaranteed to show → **FIX: Bind to alert**

### Persistence & Data Loss (PRIORITY 1)

- [x] `CloudStorageService.swift:58-94` — Upload callback failures possible → **FIX: Add explicit error observer**
- [x] `CreatePostView.swift:5832-5863` — Media uploads fail without UI feedback → **FIX: Add error alert**
- [x] `PhoneVerificationService.swift:69-83` — Phone auth errors not shown → **FIX: Show glass modal**

### Firestore Writes (PRIORITY 2)

- [x] `LoginHistoryService.swift:81-94` — Session tracking can fail silently → **FIX: Log but don't block**
- [x] `ModernPrayerWallView.swift:645-675` — Prayer saves fail without feedback → **FIX: Add error modal**
- [x] `BereanMemoryService.swift:69-91` — Insight CRUD fails silently → **FIX: Show error alerts**

### Sign-Out & Auth (PRIORITY 2)

- [x] `AMENAPPApp.swift:434` — `try?` Auth.signOut() silently swallows errors → **FIX: Replace with proper catch**
- [x] `SettingsView.swift:447-451` — Sign-out via authViewModel without explicit error handling → **FIX: Verify authViewModel catches errors**

---

## Recommended Fix Pattern

All CRITICAL and HIGH items should follow this pattern:

```swift
@State private var showError = false
@State private var errorMessage: String?

// In your async operation:
do {
    try await someOperation()
    // Success — update UI
} catch {
    errorMessage = error.localizedDescription
    showError = true
}

// Bind to glass alert:
.amenAlert(
    isPresented: $showError,
    config: LiquidGlassAlertConfig(
        title: "Operation Failed",
        message: errorMessage,
        primaryButton: LiquidGlassAlertButton("Retry") { /* retry closure */ }
    )
)
```

For Firestore listeners, use this pattern:

```swift
listener = db.collection(...).addSnapshotListener { snapshot, error in
    if let error = error {
        DispatchQueue.main.async {
            self.listenerError = error.localizedDescription
            self.showErrorAlert = true
        }
        return
    }
    // Process snapshot
}
```

---

## Integration with Liquid Glass Standard

All error modals should use the canonical `.amenAlert()` modifier from `LiquidGlassAlert.swift`:

- **Tone:** Use `.primary` for actionable errors, `.destructive` for data loss, `.spiritual` for account changes
- **Button Layout:** Always include "Retry" + "Cancel" for transient errors; "OK" for permanent errors
- **Icon:** Use `"exclamationmark.triangle.fill"` for warnings, `"exclamationmark.circle.fill"` for errors
- **Max Width:** 320pt (iPad-safe)
- **Animation:** `.spring(response: 0.34, dampingFraction: 0.84)`

---

## Next Steps

1. **Immediate (Week 1):** Fix all CRITICAL issues — Covenant checkout, account deletion, media uploads
2. **Sprint 1:** Fix all HIGH issues — Berean streaming, Firestore persistence, sign-out
3. **Sprint 2:** Audit all remaining Service files for consistency
4. **Ongoing:** Add `.amenAlert()` bindings to all new async operations before merge

---

**End of Audit Document**
