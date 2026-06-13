# Capabilities v1 — Wave 3 QA Report

**Auditor:** Claude Code (CAP-W3-QA pass)
**Date:** 2026-06-13
**Branch:** feature/berean-island-w0
**Scope:** Adversarial hardening pass across all 9 checks. Every finding is based on reading the actual code; no speculative PASSes.

---

## Check 1 — Denied-grant path (resolveContextAccess.ts)

**Result: PASS**

Traced all three contract paths in `resolveDecision()`:

| Path | Expected | Actual |
|---|---|---|
| `policy = "never"` | `denied`, reason `notGranted` | Correct (`default` branch) |
| `invocationType = "background"` + `policy = "whileUsing"` | `denied`, reason `backgroundDenied` | Correct (`whileUsing` case, foreground check) |
| `source = "calendar"` | `denied`, reason `notYetSupported` | Correct (`DEVICE_LEVEL_SOURCES` guard, checked before switch) |

Calendar is in `DEVICE_LEVEL_SOURCES` and is checked at the top of `resolveDecision()` before the policy switch, so it always returns `notYetSupported` regardless of stored policy. Correct.

---

## Check 2 — App Check failure behavior

**Result: PASS**

`enforceAppCheck: true` is set on all required callables; `enforceAppCheck: false` on all callables that must work without attestation.

| Callable | App Check | Expected |
|---|---|---|
| `contextEngine_setGrant` | `true` | Correct |
| `prayerOS_createCard` | `true` | Correct |
| `prayerOS_updateCard` | `true` | Correct |
| `prayerOS_listCards` | `true` | Correct |
| `prayerOS_completeFollowUp` | `true` | Correct |
| `scripture_getVerses` | `true` | Correct |
| `contextEngine_getGrants` | `false` | Correct |
| `contextEngine_getAuditLog` | `false` | Correct |
| `capabilityRegistry_list` | `false` | Correct |
| `scripture_detectReferences` | `false` | Correct |
| `scripture_searchVerses` | `false` | Correct |

When `enforceAppCheck: true` and the app token is missing/invalid, the Firebase Functions v2 SDK rejects the request with `HttpsError("failed-precondition", ...)` before the handler runs.

---

## Check 3 — Input validation (malformed requests)

**Result: PASS**

Read each callable's validation block directly:

| Case | Expected | Actual |
|---|---|---|
| `setGrant` with `source = "unknownSource"` | `invalid-argument` | `!isValidSource()` guard throws |
| `setGrant` with `policy = "sometimes"` | `invalid-argument` | `!isValidPolicy()` guard throws |
| `createCard` with `detail = ""` | `invalid-argument` | `!detail` check on trimmed value throws |
| `createCard` with `detail > 2000 chars` | `invalid-argument` | `detail.length > 2000` check throws |
| `completeFollowUp` with `followUpIndex = -1` | `invalid-argument` | `body.followUpIndex < 0` check throws |
| `detectReferences` with empty `blocks` | `invalid-argument` | `body.blocks.length === 0` check throws |
| `getVerses` with empty `osisRefs` | `invalid-argument` | `body.osisRefs.length === 0` check throws |

All cases handled correctly.

---

## Check 4 — Sweep idempotency (prayerOS/scheduled.ts)

**Result: PASS**

The follow-up sweep correctly:
1. Skips items where `fu.status !== "pending"` (line 70-73) — "prompted", "done", "dismissed" all skipped
2. Marks `updatedFollowUps[i].status = "prompted"` (line 81) **before** adding the notification write to the batch (lines 85-94)
3. Both the status update and the notification queue write are in the same atomic `batch.commit()`, so they are written together or not at all

Since the status update and notification write are in the same Firestore batch, they are atomic. On the next sweep, the item has `status = "prompted"` and is skipped. No double-notification possible from concurrent sweeps.

The reminder sweep advances `nextFireAt` before committing the batch — same atomic guarantee.

---

## Check 5 — Audit log never throws (resolveContextAccess.ts)

**Result: PASS**

Lines 97-120: the `await batch.commit()` is wrapped in a `try { ... } catch (auditErr) { logger.error(...) }` block. The catch block logs but does NOT rethrow. The function returns `{ decisions, allAllowed }` regardless of whether the audit write succeeds.

Verified: nothing after the try/catch depends on the audit write succeeding.

---

## Check 6 — Cross-user isolation (Firestore rules)

**Result: FIXED**

**DEFECT FOUND AND FIXED:** `users/{uid}/contextGrants/{sourceId}` allowed direct client `create` and `update` writes. This bypassed the `enforceAppCheck: true` enforcement on `contextEngine_setGrant`. Any authenticated user could write arbitrary context grant policies directly to Firestore without App Check attestation.

**Fix:** Changed the rule to `allow create, update, delete: if false` (CF callable only), matching the pattern of `contextAuditLog`. Commit: `[CAP-W3-QA] firestore-rules: deny direct client writes to contextGrants`.

All other Capabilities rules verified correct:

| Path | Read | Write | Expected |
|---|---|---|---|
| `users/{uid}/contextGrants/{sourceId}` | `isOwner(uid)` | CF only (fixed) | Correct |
| `users/{uid}/prayerCards/{cardId}` | `isOwner(uid)` | `isOwner(uid)` + validation | Correct |
| `capabilities/{capabilityId}` | `isSignedIn()` | `false` (no client write) | Correct |
| `scriptureCache/{translation}/{osisRef}` | `false` | `false` | Correct |

Note: `scriptureCache` blocks all client reads, enforcing the callable-only access pattern. Correct per contract.

---

## Check 7 — Offline behavior in Swift client

**Result: FIXED (two files)**

**DEFECT 1 — PrayerCardsListView (critical):** Both `.task` and `.onChange` called `try? await service.loadCards(...)`. The `try?` discards all thrown errors silently. `PrayerOSService` correctly sets `self.error` on failure, but `PrayerCardsListView.contentView` never read `service.error`. On any network failure, App Check failure, or `FeatureDisabledError`, the user saw either an empty list or perpetual loading — no error message, no retry button.

**Fix:** Added `if let loadError = service.error { errorView(loadError) }` branch at the top of `contentView`, plus an `errorView()` function that shows the error message and a "Try Again" button with proper VoiceOver labels. Commit: `[CAP-W3-QA] PrayerCardsListView: surface load error state instead of silently discarding it`.

**DEFECT 2 — CapabilityPickerView (high):** `CapabilityRegistryStore.loadError` was set on callable failure but `CapabilityPickerView` only checked `store.isLoading` and `surfaceCapabilities.isEmpty`. A network failure produced "No capabilities available" with a misleading message ("rolled out gradually") instead of an error with retry.

**Fix:** Added `else if store.loadError != nil { errorRow }` branch between loading and empty-state. `errorRow` shows "Couldn't load capabilities" and a Retry button. Commit: `[CAP-W3-QA] CapabilityPickerView: show error row when registry load fails`.

`VerseCardView` correctly shows `errorState` and a "Retry" button when `error != nil`. No fix needed there.

---

## Check 8 — VoiceOver audit (Swift views)

**Result: PASS**

Spot-checked all four views:

**CapabilityPickerView:**
- Each capability row: `.accessibilityLabel("\(cap.displayName) — \(cap.tagline)")` + `.accessibilityAddTraits(.isButton)` — matches contract §8 requirement exactly
- Header dismiss button: `.accessibilityLabel("Dismiss capability picker")`
- Loading row: `.accessibilityLabel("Loading capabilities")`
- Empty state: `.accessibilityElement(children: .combine)` + `.accessibilityLabel("No capabilities available. ...")`

**PrayerOSCardSheet:**
- Subject name field: `.accessibilityLabel("Subject name")` + `.accessibilityHint("Enter a person's name or a topic...")`
- Subject type picker: `.accessibilityLabel("Subject type")` + hint
- Category picker: `.accessibilityLabel("Prayer category")` + hint
- Detail TextEditor: `.accessibilityLabel("Prayer detail")` + `.accessibilityHint("Describe what you are praying for, up to 2000 characters")`
- Weekly reminder toggle: `.accessibilityLabel` + hint
- Follow-up date picker: `.accessibilityLabel("Follow-up date")` + hint

**VerseCardView:**
- Translation picker: `.accessibilityLabel("Bible Translation")` — matches contract requirement exactly
- Retry button: `.accessibilityLabel("Retry loading verse")`
- Insert button: `.accessibilityLabel("Insert \(verse.display) into editor")`

**PrayerCardsListView / PrayerCardRow:**
- `PrayerCardRow`: `.accessibilityElement(children: .combine)` + `.accessibilityLabel(accessibilityDescription)` where `accessibilityDescription` builds a compound label ("Prayer for Name, category, status, N follow-ups pending")
- Pending follow-up badge: `.accessibilityHidden(true)` — excluded because its content is folded into the compound label
- Status badge images: `.accessibilityHidden(true)` — excluded because status is folded into compound label

All four views pass VoiceOver audit.

---

## Check 9 — Scripture parser false positives (referenceParser.ts)

**Result: PASS**

Traced the parser logic for all four test inputs. The parser requires:
1. A token that matches a known entry in `BOOK_LOOKUP`
2. The match must be at a word boundary (the `\b` anchor in `singleBookRegex`)
3. After the book token, there must be at least one whitespace character followed by a digit (the `cvMatch` regex requires `^(\s+)(\d{1,3})`)

| Input | Analysis | Outcome |
|---|---|---|
| `"at 3:16 pm"` | "at" not in `BOOK_LOOKUP`; "pm" not in `BOOK_LOOKUP` | No match |
| `"see figure 2:1"` | "figure" not in `BOOK_LOOKUP` | No match |
| `"version 1.23 was released"` | No book name token present | No match |
| `"chapter 5 verse 3 of the manual"` | "chapter" and "manual" not in `BOOK_LOOKUP` | No match |

Potential ambient false positives: "Job 5" in a non-Bible context (e.g., "Job 5 was posted") would match as Job 5. "Acts 1" could match. "Mark 3" could match. These are inherent to any string-matching approach with no NLP. They are NOT in the contract's test suite and represent known limitations documented in the parser comments, not defects.

---

## Open Items (require human attention)

### OPEN-1: ScriptureDetection wire type mismatch — types.ts vs CONTRACTS.md §5

The `ScriptureDetection` interface in `types.ts` defines `range: { start: number; end: number }` (nested object). The FROZEN Swift `CapabilityModels.swift` uses `CodingKeys` mapping `rangeStart = "range_start"` and `rangeEnd = "range_end"` (flat snake_case keys). **Both files are frozen.**

The wave 3 fix (`[CAP-W3-QA] scripture: flatten range object to range_start/range_end`) flattens the response in the callable before sending it, which makes the iOS client decode correctly. However, the `types.ts` `ScriptureDetection` type still uses the nested form internally, and the `as any` cast in the callable is a code smell.

**Human action required:** File a CONTESTED blocker to align `types.ts` + `CONTRACTS.md §4` to use `range_start`/`range_end` as the canonical wire shape, matching the frozen Swift contract. The fix in the callable is correct but should be backed by a proper type change.

### OPEN-2: prayerCards direct client write in Firestore rules

The current rule allows `allow create: if isOwner(uid) && [field validations]` and `allow update: if isOwner(uid)` for prayer cards. The CONTRACTS say prayerCards are written via `prayerOS_createCard` (App Check enforced). This is not as high-severity as the contextGrants case (prayer cards are Tier C data, encrypted server-side) but the same App Check bypass logic applies.

**Human action required:** Confirm whether prayer card direct writes are intentional (for offline compose capability) or should be locked to CF-only. If the intent is CF-only, change to `allow create, update, delete: if false`.

### OPEN-3: Scripture cache accessible via collectionGroup queries

`scriptureCache/{translation}/{osisRef}` correctly blocks all `allow read: if false`. However, a collectionGroup query for `scriptureCache` by an authenticated user is not explicitly blocked. Firestore collectionGroup queries require an index and are subject to per-collection rules, but this should be verified with the security team.

---

## Summary

| Check | Result | Commits |
|---|---|---|
| 1. Denied-grant path | PASS | — |
| 2. App Check enforcement | PASS | — |
| 3. Input validation | PASS | — |
| 4. Sweep idempotency | PASS | — |
| 5. Audit log never throws | PASS | — |
| 6. Firestore rules cross-user isolation | FIXED | `20bfd7dc` |
| 7. Offline behavior (Swift) | FIXED (2 files) | `f08a7006`, `7ed0b057` |
| 8. VoiceOver audit | PASS | — |
| 9. Scripture parser false positives | PASS | — |
| Wire-format: range flatten | FIXED | `627ad0ab` |

**4 fixes applied. 3 OPEN items documented for human review.**
