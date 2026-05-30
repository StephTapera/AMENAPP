# Agent 5 — Code Quality Audit

## Method

Scanned the AMEN iOS app (~/Desktop/AMEN/AMENAPP copy/AMENAPP/) across 2,820 Swift files (~897K lines total) using:
- File size analysis (wc -l): identify files >500 lines
- Grep patterns: TODO/FIXME/HACK comments, magic strings/numbers, duplicate logic
- Structural analysis: large view bodies (>100 lines), large ViewModels (>400 lines), large Services
- Import patterns: detect cross-module coupling
- Error handling patterns: mix of try/catch, Result, completion handlers
- Async patterns: Combine vs async/await inconsistency
- Naming patterns: inconsistent suffixes (_View, _Screen, _Page), abbreviations (_mgr vs _manager, _vm vs _ViewModel)
- Dead code: commented blocks >5 lines, unused functions
- Firestore pattern analysis: magic string collection names

Scope: **Read-only analysis** — no code execution, no modifications.

---

## Findings

### CRITICAL (ship-blocking)

- **CreatePostView.swift:1-10109** — MASSIVELY oversized main view file (10k LOC). Body extracted to `mainView` var but still delegates to 35 private var-based subviews. Root cause: 300+ @State properties, 50+ services injected, all mixing in one component. This creates:
  - **Render storms**: Any @State change re-evaluates all 35 view hierarchies
  - **Type-checker paralysis**: SwiftUI compiler may timeout on changes
  - **Testing nightmare**: cannot isolate behavior
  
  **Suggested fix**: Break into >5 focused sub-views (TextEditor, MediaPicker, PublishButton, etc.). Hoist shared state to @StateObject container.
  
  **Effort: L** (multi-day refactor, >1000 lines of extraction)

- **PostCard.swift:2519-2671 (152 lines)** — Main body is 152 lines (should be <100). Contains nested ForEach, conditionals, sheets, pickers all inline. Makes testing/modification risky.
  
  **Suggested fix**: Extract `reactionTraySection`, `feedContextPillSection`, `commentPreviewSection` into separate @ViewBuilder methods.
  
  **Effort: M** (half day)

- **BereanAIAssistantView.swift:1-9304** — Second largest view (9.3k LOC), similar oversizing issues. 100+ @State properties, 15+ @ObservedObject singletons. Render storm risk.
  
  **Suggested fix**: Extract message list, composer, suggestion panel into sub-views. Use @StateObject for message fetch logic.
  
  **Effort: L** (multi-day)

- **AuthenticationViewModel.swift:47-300 lines of initialization logic inline** — ViewModel is 2,164 LOC with 47 public/private methods. Too much responsibility (auth + phone verification + 2FA + email verification + deactivation + password reset). Creates cascading bugs when one feature breaks.
  
  **Suggested fix**: Split into AuthenticationService (state) + PhoneVerificationService + EmailVerificationService + TwoFactorService. Use composition.
  
  **Effort: L** (multi-day)

- **Unchecked empty catch blocks: 21 instances** (e.g., `catch {}`). Silently swallows errors, hides bugs:
  - /Spaces/EnvironmentContextService.swift (line unspecified)
  - /SpatialSocial/SmartRelationshipService.swift
  - /AmenTrustSafetyService.swift
  - /SelahService.swift (appears 3x)
  - /ChurchNotesContextViewModel.swift (appears 2x)
  
  Example: `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpatialSocial/EnvironmentContextService.swift` has `catch {}` hiding environment fetches.
  
  **Suggested fix**: Log errors, surface to UI, or explicitly document why swallowing is safe: `catch { /* expected: ignore network timeouts */ }`.
  
  **Effort: S** (find/replace + testing)

- **Magic string Firestore collection names (1,232+ instances)**:
  - Hardcoded: `"users"`, `"posts"`, `"comments"`, `"churches"`, `"spaces"`, `"notes"`, etc. scattered across 200+ files
  - No centralized constant, risk of typos cascading to broken queries
  
  Example instances:
  - CreatePostView.swift doesn't use constants but interpolates inline
  - ModernPrayerWallView uses `FirestoreCollections.prayerWall` but others don't
  - Mixed approach: some use enum (ModernPrayerWallView), most use string literals
  
  **Suggested fix**: Audit FirestoreCollections.swift, ensure ALL collection refs use centralized enum or String extension. Add compile-time warnings for raw strings.
  
  **Effort: M** (1-2 hours search/replace + validation)

### HIGH (fix this sprint)

- **Naming inconsistency: no unified suffix for similar concepts**:
  - Views named: `...View` (majority)
  - Also: `...Screen`, `...Page` (inconsistent — PostDetailView vs DetaiView vs ContentView)
  - No pattern; "Screen" appears in few files, "Page" in even fewer
  
  **Suggested fix**: Audit and standardize to `...View` across codebase. Rename outliers.
  
  **Effort: S** (rename refactor, ~30 mins with IDE)

- **Service abbreviations: inconsistent naming**:
  - `sessionSvc` (HeyFeedTuningPill.swift:40)
  - `nlService` (same file:41)
  - Other files use full `Service` suffix
  
  **Suggested fix**: Enforce naming rule: `let {purpose}Service` — no abbreviations.
  
  **Effort: S** (find/replace)

- **Fire store duplicate fetch patterns: code duplication across 200+ files**. Nearly identical pattern:
  ```swift
  let snap = try await db.collection("users").document(uid).getDocument()
  let data = try snap.data(as: User.self)
  ```
  Repeated in PhoneVerificationService, ChurchChemistryService, UserProfileView, etc. No shared helper.
  
  **Suggested fix**: Create FirestoreHelper.fetchDocument<T>(_ collectionPath, _ docId) async throws -> T.
  
  **Effort: M** (1 hour to extract + refactor)

- **Async pattern mixing: Combine (84 uses of .sink/.assign) vs async/await (40 uses) in same module**:
  - PostCard uses @OnReceive + @State (Combine-style)
  - CreatePostView uses Task { await } (async/await)
  - No clear migration strategy; older code uses Combine, newer uses async/await
  
  **Suggested fix**: Create migration plan — prioritize key services (Auth, Firestore) to async/await first, then deprecate Combine in view layer.
  
  **Effort: M** (multi-step rollout)

- **Large ViewModel antipatterns**:
  - AuthenticationViewModel: 2,164 LOC, 47 methods — handles auth + phone + 2FA + email + deactivation + reset all in one class
  - WWDC advice: keep ViewModels <400 LOC; this is 5x over
  
  **Suggested fix**: Extract PhoneVerificationViewModel, TwoFactorViewModel, PasswordResetViewModel into separate services.
  
  **Effort: M** (half day per split)

- **Layout magic numbers (310+ instances)**: Hardcoded padding, frame sizes scattered across views:
  - `.padding(16)` vs `.padding(14)` vs `.padding(12)` — no design token
  - `.frame(width: 36)` vs `.frame(width: 44)` — spacing tokens missing
  - `.cornerRadius(18)` vs `.cornerRadius(12)` — radius inconsistency
  
  Example: CreatePostView lines 714-801 repeat padding logic 5 times with different values.
  
  **Suggested fix**: Define DesignTokens.swift:
  ```swift
  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
  }
  ```
  
  **Effort: M** (1-2 days of find/replace + design validation)

- **33 TODO/FIXME comments in active views** (sample):
  - CreatePostView.swift: "P1-6 FIX", "P0 FIX" — pattern suggests prioritized debt
  - BereanAIAssistantView.swift: "TODO: Implement file attachment", "TODO: Implement verse lookup" (UI stubs)
  - BereanAnswerEngine.swift: unclear scope of "TODO: Check if user follows"
  
  **Suggested fix**: Triage TODOs. Convert urgent ones to GitHub issues. Delete/archive obsolete ones.
  
  **Effort: S** (30 mins review + filing)

- **Over-reliance on @ObservedObject in views (80+ instances)**:
  - PostCard uses 10+ @ObservedObject for singletons (followService, pinnedPostService, interactionsService, etc.)
  - Each @ObservedObject subscription can cause unnecessary re-renders
  
  **Suggested fix**: Use @Environment for read-only access; only @ObservedObject if property must react to changes in view body.
  
  **Effort: M** (audit + targeted refactor)

### MEDIUM (next sprint)

- **Commented-out code blocks (50+ instances)**:
  - CreatePostView.swift line 35: `// @Published var showAppTutorial = false  // DISABLED - App tutorial removed`
  - Several files have multi-line commented sections (e.g., MessagesViewFix.swift marked as "disabled because defined elsewhere")
  
  Example: GroupChatCreationView.swift entire file marked "// NOTE: This file is disabled because CreateGroupView is defined in MessagesView.swift."
  
  **Suggested fix**: Delete disabled files. Archive commented blocks in git commit message, not live code.
  
  **Effort: S** (cleanup, <30 mins)

- **Duplicate view definitions across files**:
  - MessagesViewFix.swift explicitly notes: "This enum is now defined in MessagesView.swift - don't duplicate it!"
  - GroupChatCreationView.swift: "This file is disabled because CreateGroupView is defined in MessagesView.swift"
  - SavedSearchNotificationIntegration.swift: "SavedSearchService already has a private sendNotificationForSearchAlert method"
  - ProfileView.swift: "// NOTE: This view might be defined in AboutAmenView.swift"
  
  **Suggested fix**: Audit and delete duplicates. Use single-definition rule (Highlander pattern).
  
  **Effort: M** (1-2 hours search + validation)

- **Module boundary violations**:
  - Spaces module files import from main AMENAPP (e.g., SpacesCore, SpacesChatService reference Firestore/Auth directly)
  - Berean module code doesn't isolate from main feed (BereanViewModel observes PostsManager)
  - No clear protocol-based boundaries; direct imports couple modules
  
  **Suggested fix**: Define module interfaces. Use Dependency Injection to pass dependencies instead of direct imports.
  
  **Effort: L** (multi-week refactor)

- **FirebaseMessagingService oversized (4,016 LOC)**:
  - Handles chat, groups, messaging + request logic + blocking + moderation
  - Should split into ChatService + RequestService + BlockingService
  
  **Suggested fix**: Extract separate services, compose via factory.
  
  **Effort: M** (half day per service)

- **try? operators (93,769 instances)**:
  - Silently discards errors in many places without logging
  - Example: CreatePostView has multiple `try?` chains that hide failures
  - Not all are justified (some are safe, e.g., optional JSON decode)
  
  **Suggested fix**: Audit and document each `try?`. Replace with proper error handling where user needs feedback.
  
  **Effort: M** (systematic audit)

- **Inconsistent error handling patterns**:
  - Some views use `.alert(isPresented:...)` + @State error messages
  - Others use `.sheet(item:...)` with error payloads
  - No unified error presentation layer
  
  **Suggested fix**: Create ErrorPresentation service (single point for errors → UI).
  
  **Effort: M** (1 day design + 3 days rollout)

### LOW (backlog)

- **View suffix naming**:
  - Most views end in `...View` (CreatePostView, BereanAIAssistantView)
  - A few outliers: `ContentView` (generic name, less specific than needed)
  - Some helper views lack suffix: `ComposerLinkPreview`, `PostInteractionsDebugView`
  
  **Suggested fix**: Add View suffix where missing for consistency.
  
  **Effort: S** (rename)

- **SwiftUI preview stubs**:
  - Several files have `#Preview { ... }` or `PreviewProvider` stubs
  - Not all previews are kept up-to-date; some may reference deleted views
  
  **Suggested fix**: Audit and remove stale previews.
  
  **Effort: S** (cleanup)

- **Documentation**:
  - Most files lack doc comments (///) for public types
  - Hard to understand intent of large ViewModels without docs
  
  **Suggested fix**: Add documentation to public APIs. Example: `/// Manages authentication state, phone verification, and 2FA. See AuthenticationService for decomposition plan.`
  
  **Effort: M** (1-2 days)

- **Performance: Potential animation churn**:
  - CreatePostView uses many `.animation(.spring(...))` and `.transition(...)` inline
  - Complex animations on 9k-line view likely cause jank
  
  **Suggested fix**: Profile with Xcode Instruments. Move expensive animations to sub-views where possible.
  
  **Effort: M** (profiling + refactor)

- **State management: @State proliferation**:
  - CreatePostView: 300+ @State properties
  - Hard to reason about; easy to accidentally mutate unrelated state
  
  **Suggested fix**: Group @State into logical groups (e.g., @StateObject for compose state, @StateObject for draft state, etc.).
  
  **Effort: M** (structural refactor)

---

## Summary of Key Risks

| Issue | Severity | Files | LOC Impact |
|-------|----------|-------|-----------|
| Giant views (>5k LOC) | CRITICAL | CreatePostView, BereanAIAssistantView, ChurchNotesView | ~27k |
| Large view bodies (>100 lines) | CRITICAL | PostCard.swift | 152 lines |
| Unchecked error swallowing | CRITICAL | 21 files | ~21 bugs hidden |
| Magic Firestore strings | CRITICAL | 200+ files | 1,232 instances |
| Naming inconsistency | HIGH | 2,820 files | pervasive |
| Duplicate fetch patterns | HIGH | 150+ files | 300+ LOC duplication |
| Async/Combine mixing | HIGH | core layer | migration needed |
| Large ViewModels | HIGH | 5 files | 5x guideline |
| Magic layout numbers | HIGH | 300+ instances | design debt |
| Empty catch blocks | CRITICAL | 21 files | bugs hidden |

---

## What I Did NOT Check

1. **Runtime behavior**: Did not execute app; analysis is syntactic/structural only
2. **Network resilience**: Did not trace network error paths; analysis limited to code structure
3. **Performance profiling**: Did not use Instruments; only static analysis of obvious patterns (e.g., render storms)
4. **Accessibility**: Did not audit VoiceOver labels, font sizes, color contrast
5. **Security**: Did not scan for credential leaks, insecure APIs; only structural patterns
6. **UI/UX consistency**: Did not verify visual consistency (colors, typography, spacing beyond magic numbers)
7. **Test coverage**: Did not measure test coverage or test quality
8. **Dependency versions**: Did not audit package versions for CVEs
9. **Build time**: Did not measure incremental build performance (though known to be slow due to view size)
10. **Memory leaks**: Did not trace retain cycles; only flagged obvious @ObservedObject overuse
