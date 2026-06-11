# Firestore Rules / Index Coverage Audit — REPORT ONLY

**Date:** 2026-06-09 · **Author lane:** onboarding-auth-remediation (claude)
**Scope:** Diff every collection referenced in code against `firestore.rules` and `firestore.indexes.json`.
**⚠️ This is a read-only report. No edits were made to `firestore.rules` or `firestore.indexes.json`** (shared multi-agent hotspots). Fixes are scheduled as an explicit batch below.

---

## Headline: security posture is SOUND (deny-by-default confirmed)

`firestore.rules:2240` ends with:
```
match /{document=**} {
  allow read, write: if false;
}
```
Every collection not explicitly matched is **fail-closed**. So unruled collections are *inaccessible to clients*, never *wide open*. **There is no missing-rule security hole.** The gaps below are therefore **functional** (a client-accessed collection with no rule is silently blocked → broken feature), not security exposures.

## Counts

| Metric | Count |
|--------|-------|
| Distinct collection segments in `firestore.rules` (all depths) | 147 |
| Indexed `collectionGroup`s in `firestore.indexes.json` | 38 |
| Distinct collections referenced in code (JS/TS prod + Swift) | ~656 |
| Collections written/read in code with **no rule at any depth** | **588** |
| …of those, referenced by the **Swift client** (deny-by-default actively blocks) | **551** |

Full machine-readable lists (for the fix batch):
- `RULES_INDEX_AUDIT_all_unruled.txt` — all 588 unruled.
- `RULES_INDEX_AUDIT_client_gaps.txt` — the 551 client-accessed gaps.

---

## How to read the 551 client gaps

They split into two very different buckets:

### A. Server-only collections — deny-by-default is CORRECT (no rule needed)
These should only ever be written by Cloud Functions via the Admin SDK (which bypasses rules). Clients must never touch them directly; the deny is the intended design. **These are NOT bugs** — flag only if a Swift path actually tries to read them (which would itself be the bug).

Examples confirmed in the security-sensitive sweep (all correctly denied):
`advancedModerationLogs, aiUnsafeReports, moderation*, moderation_queue, imageModerationLogs, safetyAuditLog, safetyDecisions, safetyEvents, securityEvents, security_alerts, trustEvents, trustRecords, trustScoreQueue, trustSnapshots, userTrustScores, shadowBans, enforcementHistory, enforcement_actions, user_enforcement, crisisDetection*, crisis_session_events, backupCodes, keyBundles, usedOTPKs, otpRequests, encryptedMessages, deletionRequests, quarantinedContentHashes, brigadingAlerts, contentSafetyLogs, messageSafetyEvents`.

> If any of these are read/written from the **client** today, that call is failing silently — the fix is to move it server-side, NOT to open a rule.

### B. Client-feature collections — genuine BROKEN-feature gaps (need explicit rules)
Collections the app legitimately reads/writes from the device but that have no rule, so the feature is silently dead under deny-by-default. High-signal candidates from the client-gap list to triage first:
`savedChurches, savedChurch, churchNotesSaved, churchNoteFolders, churchNoteReflections, churchVisitSessions, churchJourneys, prayerRooms, prayerEntries, prayerReflections, koraCheckIns, koraJournalEntries, koraCircles, selahEntries, selahNotes, selahSavedScripture, savedVerses, savedResources, bookmarkedMedia, readingPlans, studyPlans, studyProgress, mentorProfiles, mentorshipSessions, connectSpaces, connectMemberships, spaceMemberships, communityMemberships, covenants, covenantMemberships, creatorProfiles, creatorPosts, devices, deviceTokens, loginHistory, contacts, feedPreferences, userSettings, prayerReminders, wellnessCheckIns`.

> Each needs an owner-scoped rule (`allow read, write: if isSignedIn() && request.auth.uid == resource.data.userId` or subcollection-under-`/users/{uid}` pattern). Many are `users/{uid}/X` subcollections that simply were never added.

---

## Index coverage

38 `collectionGroup` indexes exist (`posts`×15, `users`×6, `comments`×5, `conversations`×5, `notifications`×3, `follows`/`groups`/`works`×2–4, etc.). Index gaps don't fail closed — they surface as **runtime query errors** (`FAILED_PRECONDITION: The query requires an index`) the first time a compound/`orderBy`+`where` query runs. They cannot be enumerated statically with confidence (query shape ≠ collection name), so the fix batch should:
1. Take each **bucket-B** collection that gets a rule,
2. grep its Swift query sites for `whereField(...).order(by:)` / multiple `whereField`,
3. add the matching composite index in the same batch.

Collections with rules **and** indexes (healthy): `posts, users, comments, conversations, messages, follows, notifications, prayers, events, edges, noteShares, savedPosts, savedSearches, knowledgeNodes, works, ingestionJobs, processingJobs, ocrResults, transcripts, reflections, blockedUsers`.

---

## Scheduled fix batch (NOT done here — shared hotspot files)

Per the manifest hotspot rule (`firestore.rules` / `firestore.indexes.json` = append-only, smallest diff, one owner at a time):

1. **Triage `RULES_INDEX_AUDIT_client_gaps.txt`** into Bucket A (server-only — leave denied; fix any client caller) vs Bucket B (needs rule).
2. **Append owner-scoped rules** for Bucket B, grouped logically (church/, prayer/, selah/, kora/, creator/, connect/, covenant/ families), smallest diff, each above the catch-all.
3. **Add composite indexes** for the query patterns those collections use.
4. Re-run this audit to confirm the client-gap count drops to ~0 (only true server-only collections remain unruled).

Owner: schedule as a single-agent claim on `firestore.rules` + `firestore.indexes.json` in `AGENT_LANES.md` (no concurrent editor).
