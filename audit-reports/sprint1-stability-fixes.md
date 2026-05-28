# Sprint 1 Stability Fixes — Memory Leak Closures
Date: 2026-05-27  
Branch: berean/ui-rebuild-liquid-glass-v1  
Build result: PASS (0 errors, 0 warnings added)

---

## Fix 1 — SavedSearchNotificationHelper: discarded observer token

**File:** `AMENAPP/SavedSearchNotificationIntegration.swift`

**Root cause:** `registerObserver()` called `NotificationCenter.default.addObserver(forName:object:queue:using:)` and discarded the returned `NSObjectProtocol` token. Block-based observers are never automatically removed — the closure fires indefinitely until `removeObserver(_:)` is called on the token. With no stored reference, removal was impossible, creating a zombie observer that fires on every `openSavedSearch` notification for the lifetime of the process.

**Fix applied:**
- Added `private static var observerToken: NSObjectProtocol?` to the struct.
- `registerObserver()` now saves the return value: `observerToken = NotificationCenter.default.addObserver(...)`.
- `registerObserver()` removes any previous registration before creating a new one — prevents duplicate observers on repeated calls (e.g. re-login).
- Added `unregisterObserver()` static method: removes and nils the token. Call this from app teardown or logout.

**Pattern note:** `SavedSearchNotificationHelper` is a `struct` with only `static` members. The token is `static var`, which is the correct approach for a static-only helper that cannot have instance `deinit`.

---

## Fix 2 — VisitPlanService.listenToUpcomingVisitPlans: caller audit

**Files:** `AMENAPP/VisitPlanService.swift`, `AMENAPP/FirstVisitCompanionViewModel.swift`

**Findings at call sites:**  
`listenToUpcomingVisitPlans` is defined in `VisitPlanService` and returns a `ListenerRegistration`. A search of the entire AMENAPP source tree found **zero call sites** — the method is defined but never invoked. No active listener leak exists today.

However, the intended consumer (`FirstVisitCompanionViewModel`) had no plumbing to store or clean up a `ListenerRegistration` if `listenToUpcomingVisitPlans` were ever called. This was a latent leak vector: any future code that called the method would almost certainly discard the registration (no stored property existed to receive it).

**Fix applied to `FirstVisitCompanionViewModel`:**
- Added `private var visitPlanListener: ListenerRegistration?` stored property.
- Added `startListening()`: removes any stale registration, calls `listenToUpcomingVisitPlans`, stores the result, captures `[weak self]` in the callback.
- Added `stopListening()`: calls `.remove()` and nils the property.
- Added `deinit`: calls `visitPlanListener?.remove()` as a final safety net regardless of whether `stopListening()` was called by the View.

**Usage guidance for Views:**  
Call `viewModel.startListening()` in `.onAppear` and `viewModel.stopListening()` in `.onDisappear`. The `deinit` guard ensures cleanup even if `onDisappear` is skipped.

---

## Bonus — AmenSpacesDiscussionDiscoveryService: [weak self] check

**File:** `AMENAPP/AmenSpacesDiscussionDiscoveryService.swift`

**Result: CONFIRMED HEALTHY.** Both `addSnapshotListener` calls inside the service use `[weak self]` capture lists:

```
.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
```

The fix from the previous session is intact. No regression detected.

---

## Summary

| # | File | Issue | Status |
|---|------|-------|--------|
| 1 | SavedSearchNotificationIntegration.swift | `addObserver` token discarded — zombie observer | Fixed |
| 2 | FirstVisitCompanionViewModel.swift | No `ListenerRegistration` storage or `deinit` — latent leak | Fixed |
| B | AmenSpacesDiscussionDiscoveryService.swift | [weak self] previously fixed | Verified OK |

Build: **PASS** — 0 errors after both fixes.
