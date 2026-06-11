# Verification Test Suite (unverified-stack coverage)

New, additive test files covering the previously-unverified safety stack. All
names below are real test identifiers.

## Files & tests

### 1. NoteShare access control + Settings owner-only — `Backend/verification/noteShareAccess.rules.test.js`
Firestore rules unit tests against the **canonical** repo-root `firestore.rules`.
- `noteShare_revoked_returns_nothing`
- `noteShare_signedOut_blocked_entirely`
- `noteShare_public_allowed_for_signedIn`
- `noteShare_nonConnection_blocked_from_connections_visibility`
- `noteShare_connection_allowed_for_connections_visibility`
- `noteShare_nonMember_blocked_from_church_visibility`
- `noteShare_member_allowed_for_church_visibility`
- `noteShare_author_allowed_when_active`
- `noteShare_list_denied`
- `noteShare_clientWrite_denied`
- `settings_owner_can_read`
- `settings_owner_can_write`
- `settings_nonOwner_read_blocked`
- `settings_nonOwner_write_blocked`
- `settings_signedOut_blocked`

### 2. Church Notes draft lifecycle — `AMENAPPTests/ChurchNotesDraftLifecycleTests.swift`
Swift Testing, isolated temp directory.
- `draft_saveThenLoad_roundTrips`
- `draft_relaunch_restoresFromDisk`
- `draft_kill_removesDraft`
- `draft_saveEmpty_doesNotPersist`
- `draft_loadMissing_returnsNil`
- `draft_overwrite_keepsLatest`

### 3. Presence fail-closed + Comment enforcement — `AMENAPPTests/PresenceAndCommentEnforcementTests.swift`
- `presence_defaultPreferences_areConservative` ✅ implemented (model-level fail-closed)
- `presence_quietMode_suppressesAllSignals` ⏸ disabled — needs `eligibleSignals` pure overload / settable state seam
- `presence_belowThresholdOrZeroConfidence_notEligible` ⏸ disabled — needs seam + `PresenceSignal` fixture factory
- `comment_missingOrBlockModerationDecision_rejectedByAddComment` ⏸ disabled — needs `ModerationGatewayService` DI seam in `PostInteractionsService`
- `comment_directClientRTDBWrite_fails` ⏸ disabled — no root `database.rules.json`; needs RTDB rules path + emulator harness

> Disabled tests are named slots carrying the exact contract + blocker, so the
> owner enables each with a one-line seam. They run and report as skipped (with
> reason), never as false green.

## Run commands

**Firestore rules tests (suite 1):**
```bash
cd Backend && firebase emulators:exec --only firestore \
  "npx jest --testPathPattern=verification/ --testEnvironment node"
```
(Deps: `@firebase/rules-unit-testing@^3`, `firebase@^10`, `jest` in `Backend/devDependencies`.)

**Swift tests (suites 2 & 3):**
```bash
xcodebuild test -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AMENAPPTests/ChurchNotesDraftLifecycleTests \
  -only-testing:AMENAPPTests/PresenceFailClosedTests \
  -only-testing:AMENAPPTests/CommentEnforcementTests
```
(Or ⌘U in Xcode.)
