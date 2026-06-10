# Verification Test Suite (unverified-stack coverage)

New, additive test files. All names are real test identifiers.

> Target membership: the two Swift files must be added to the `AMENAPPTests`
> target. `project.pbxproj` is **Codex's claimed hotspot** — coordinate that add
> with the Codex lane (see AGENT_LANES.md). The JS suite needs no pbxproj change.

## 1. NoteShare access + Settings owner-only — `Backend/verification/noteShareAccess.rules.test.js`
Firestore rules unit tests vs canonical repo-root `firestore.rules`. `node --check` ✅.
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
- `settings_owner_can_read` · `settings_owner_can_write`
- `settings_nonOwner_read_blocked` · `settings_nonOwner_write_blocked`
- `settings_signedOut_blocked`

## 2. Church Notes draft lifecycle — `AMENAPPTests/ChurchNotesDraftLifecycleTests.swift`
Swift Testing; shared service + unique per-test keys + cleanup (stable surface).
- `draft_saveThenLoad_roundTrips`
- `draft_relaunch_restoresFromDisk`
- `draft_kill_removesDraft`
- `draft_saveEmpty_doesNotPersist`
- `draft_loadMissing_returnsNil`
- `draft_overwrite_keepsLatest`

## 3. Presence fail-closed + Comment enforcement — `AMENAPPTests/PresenceAndCommentEnforcementTests.swift`
- `presence_defaultPreferences_areConservative` ✅ implemented
- `presence_quietMode_suppressesAllSignals` ⏸ disabled — needs `eligibleSignals` pure overload / settable-state seam
- `presence_belowThresholdOrZeroConfidence_notEligible` ⏸ disabled — needs seam + `PresenceSignal` fixture factory
- `comment_missingOrBlockModerationDecision_rejectedByAddComment` ⏸ disabled — needs `ModerationGatewayService` DI seam in `PostInteractionsService`
- `comment_directClientRTDBWrite_fails` ⏸ disabled — no root `database.rules.json`; needs RTDB rules path + emulator harness

> Disabled tests are named slots with the exact contract + blocker; the owner enables each with a one-line seam. They report skipped (with reason), never false green.

## Run commands
**Firestore rules (suite 1):**
```bash
cd Backend && firebase emulators:exec --only firestore \
  "npx jest --testPathPattern=verification/ --testEnvironment node"
```
**Swift (suites 2 & 3, after target membership):**
```bash
xcodebuild test -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:AMENAPPTests/ChurchNotesDraftLifecycleTests \
  -only-testing:AMENAPPTests/PresenceFailClosedTests \
  -only-testing:AMENAPPTests/CommentEnforcementTests
```
