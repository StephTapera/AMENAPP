# AMEN App Codebase Audit — March 2026

## P0 — Critical (Crash / Data Loss / Privacy)

### 1. 332 Duplicate "Copy 2" Files
- **190 duplicate `.swift` files** and **106 duplicate `.md` files** with " 2" suffixes
- Causes compile errors, symbol collisions, confusion about canonical source
- **Fix:** Delete all " 2" files after confirming no unique changes vs originals

### 2. Force Unwraps in Safety-Critical Code
- `CommentSafetySystem.swift` and `NotificationAggregationService.swift` use `.first!`
- **Fix:** Replace with `.first` (optional) or guard-let

### 3. Continuation Never Resumes — `MediaModerationPipeline.swift`
- `waitForApproval()` (~line 333) has no timeout and no error path
- If Cloud Function crashes, CreatePostView spinner hangs forever
- **Fix:** Add 60-second timeout race; handle error branch

### 4. Continuation Double-Resume — `CloudStorageService.swift`
- Lines 57-94: Both `.failure` and `.success` observers can resume the same continuation
- **Fix:** Use a Bool flag to ensure single resumption

### 5. Missing `[weak self]` in Firestore Listeners
- `ProfileView.swift`, `UserProfileView.swift` (2 listeners), `UnifiedChatView.swift`, `FirebaseMessagingService+RequestsAndBlocking.swift`
- Causes retain cycles — views never deallocate, listeners keep firing
- **Fix:** Add `[weak self]` to all snapshot listener closures

### 6. Firestore Listener Leaks
- **40 `addSnapshotListener` calls** across 30 files, only **13 removals** across 9 files
- Key offenders: `FirebaseMessagingService.swift` (5 listeners, 1 removal), `ChurchNotesService.swift` (2 listeners, 0 removals)
- **Fix:** Ensure every listener has removal in `deinit`/`onDisappear`; centralize through `ListenerRegistry.swift`

### 7. Duplicate Post Creation Risk
- `CreatePostView.swift` has `inFlightPostHash` guard but timing window between validation and Firebase write allows rapid double-tap
- **Fix:** UUID-based idempotency keys; disable button for 2s post-submission

### 8. Block Enforcement Gaps
- `BlockService` loads blocked users but enforcement NOT guaranteed in all 50+ content views
- **Fix:** Create privacy gate function all views must call before rendering user content

### 9. Non-Atomic Message Dedup
- `UnifiedChatView.swift` uses `inFlightMessageIDs` but doesn't do atomic check-and-add
- **Fix:** Add to set BEFORE starting async task

### 10. 216 TODO/FIXME Comments
- Many marked "P0 FIX" or "P1 FIX" — known but unresolved bugs
- **Fix:** Triage and resolve P0-tagged items first

---

## P1 — High Priority (Lag / Stale UI / Broken Flows)

### 1. Silent Auth Failures
- `TrustByDesignMessagingControls.swift` (line 307) silently returns when `currentUser` is nil
- UI shows "sent" but message never created
- **Fix:** Throw errors or show user-visible feedback

### 2. Badge Count Race Condition
- `BadgeCountManager.swift`: Two independent listeners both call `requestBadgeUpdate()`, causing flickers
- **Fix:** Coalesce updates with proper locking

### 3. No Pagination on Major Views
- `TestimoniesView.swift`, `PrayerView.swift` load entire collections into memory
- **Fix:** Cursor-based pagination with `.limit(25)` + `.startAt(lastSnapshot)`

### 4. Missing Error UI
- `CommentsView`, `CreatePostView`, `UnifiedChatView` show loading but no error recovery
- **Fix:** Error banner + "Retry" button for recoverable errors

### 5. 4 Separate Image Cache Implementations
- `ImageCache.swift`, `CachedAsyncImage.swift`, `UserProfileImageCache.swift`, `NotificationImageCache.swift`
- **Fix:** Consolidate to single `ImageCacheManager` with TTL invalidation

### 6. Notification Duplication Risk
- `NotificationService.swift` has two listeners merged asynchronously; both can fire simultaneously
- **Fix:** Extend dedup logic; use `SmartNotificationDeduplicator` everywhere

### 7. Search Not Debounced
- Chat/comments search fires on every keystroke
- **Fix:** 300ms debounce minimum; cancel previous task on new input

### 8. `@MainActor` Discipline
- 40+ Firestore listeners call back on background threads; `@Published` updates may happen off main thread
- **Fix:** Audit all listener callbacks for main-thread safety

### 9. No Unit Test Coverage
- 767 Swift files with minimal test suite
- **Fix:** Add tests for critical flows (messaging, auth, post creation)

### 10. 966 Orphaned Documentation Files
- Status docs, deployment guides, session notes cluttering repo
- **Fix:** Move to `docs/` or wiki; delete duplicates

---

## P2 — Polish / Consistency

### 1. Flat File Structure
- 482 files in single `AMENAPP/` directory with no feature-based organization
- **Fix:** Reorganize by feature (OpenTable/, Prayer/, Messages/, etc.)

### 2. God Files
- `ContentView.swift` contains 43 classes/structs
- **Fix:** Decompose into focused files

### 3. Overlapping Services
- 9 safety services, 5 notification services, 4 search services
- **Fix:** Consolidate where responsibilities overlap

### 4. No Dependency Injection
- All services are hardcoded singletons
- **Fix:** Consider protocol-based DI for testability

### 5. Inconsistent Naming
- `UserModel.swift` vs `ModelsUser.swift`; mixed `*Service` / `*Manager` naming
- **Fix:** Standardize conventions

### 6. 41 Shell Scripts in Root
- Deploy scripts clutter project root
- **Fix:** Move to `scripts/` directory

---

## Stress Test Script

1. **Post Duplication:** Tap publish twice rapidly (<500ms) → expect 1 post
2. **Listener Leaks:** Navigate in/out of feed 50 times → memory should plateau
3. **Notification Dedup:** Account A posts → Account B sees exactly 1 badge increase
4. **Block Enforcement:** Block User X → refresh feed → search → User X invisible everywhere
5. **Message Race:** Slow 3G + tap send 3x rapidly → expect 1 message
6. **Rapid Follow:** Tap follow/unfollow 10x → final state matches server

## Acceptance Criteria

- [ ] No duplicate posts on rapid submit
- [ ] All async operations debounced (300-500ms)
- [ ] All Firestore listeners registered at most once per view lifecycle
- [ ] Memory stable after 100 navigation cycles
- [ ] All error states show recovery options
- [ ] Blocked users cannot view content in ANY path
- [ ] Pagination on feeds >100 items
- [ ] Badge count matches reality
- [ ] All buttons have press feedback + loading state
- [ ] No ghost messages from network races
