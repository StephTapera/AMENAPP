# Firestore Rules / Index Coverage Audit — REPORT ONLY

**Date:** 2026-06-09 · **Lane:** onboarding-auth-remediation (claude)
**⚠️ Read-only report. No edits to `firestore.rules` / `firestore.indexes.json`** (shared hotspots). Fixes scheduled as an append-only batch below.

## Headline: security posture is SOUND (deny-by-default confirmed)
`firestore.rules` ends with:
```
match /{document=**} { allow read, write: if false; }
```
Every unmatched collection is **fail-closed**. Unruled ≠ open. **No missing-rule security hole.** Gaps below are *functional* (client-accessed collection with no rule → silently blocked → broken feature), not exposures.

## Counts
| Metric | Count |
|--------|-------|
| Rule path-segments in `firestore.rules` (all depths) | 147 |
| Indexed `collectionGroup`s in `firestore.indexes.json` | 38 |
| Distinct collections referenced in code (JS/TS + Swift) | ~656 |
| Collections in code with **no rule at any depth** | **588** |
| …referenced by the **Swift client** (deny actively blocks) | **551** |

Machine-readable: `RULES_INDEX_AUDIT_all_unruled.txt` (588), `RULES_INDEX_AUDIT_client_gaps.txt` (551).

## Two buckets

### A. Server-only — deny-by-default is CORRECT (no rule needed)
Admin-SDK-written only; clients must never touch. Correctly denied (NOT bugs; if a client path reads them, *that* is the bug — move it server-side):
`advancedModerationLogs, aiUnsafeReports, moderation*, moderation_queue, imageModerationLogs, safetyAuditLog, safetyDecisions, safetyEvents, securityEvents, security_alerts, trustEvents, trustRecords, trustScoreQueue, trustSnapshots, userTrustScores, shadowBans, enforcementHistory, enforcement_actions, user_enforcement, crisisDetection*, crisis_session_events, backupCodes, keyBundles, usedOTPKs, otpRequests, encryptedMessages, deletionRequests, quarantinedContentHashes, brigadingAlerts, contentSafetyLogs, messageSafetyEvents`.

### B. Client-feature — genuine BROKEN-feature gaps (need owner-scoped rules)
Legitimately client-accessed but unruled → silently dead under deny-by-default. Triage first:
`savedChurches, savedChurch, churchNotesSaved, churchNoteFolders, churchNoteReflections, churchVisitSessions, churchJourneys, prayerRooms, prayerEntries, prayerReflections, koraCheckIns, koraJournalEntries, koraCircles, selahEntries, selahNotes, selahSavedScripture, savedVerses, savedResources, bookmarkedMedia, readingPlans, studyPlans, studyProgress, mentorProfiles, mentorshipSessions, connectSpaces, connectMemberships, spaceMemberships, communityMemberships, covenants, covenantMemberships, creatorProfiles, creatorPosts, devices, deviceTokens, loginHistory, contacts, feedPreferences, userSettings, prayerReminders, wellnessCheckIns`.
Each needs an owner-scoped rule (`isSignedIn() && request.auth.uid == resource.data.userId`, or `users/{uid}/X` subcollection pattern).

## Index coverage
38 `collectionGroup` indexes (`posts`×15, `users`×6, `comments`×5, `conversations`×5, `notifications`×3, …). Index gaps don't fail closed — they surface as runtime `FAILED_PRECONDITION: requires an index`. Can't be enumerated statically (query shape ≠ collection name). Fix batch: for each Bucket-B collection that gets a rule, grep its Swift query sites for `whereField(...).order(by:)`/multi-`whereField` and add the matching composite index.
Healthy (rule + index): `posts, users, comments, conversations, messages, follows, notifications, prayers, events, edges, noteShares, savedPosts, savedSearches, knowledgeNodes, works, ingestionJobs, processingJobs, ocrResults, transcripts, reflections, blockedUsers`.

## Scheduled fix batch (NOT done — shared hotspot)
1. Triage `RULES_INDEX_AUDIT_client_gaps.txt` → Bucket A (leave denied; fix client callers) vs Bucket B (needs rule).
2. Append owner-scoped rules for Bucket B (grouped: church/prayer/selah/kora/creator/connect/covenant families), smallest diff, above the catch-all.
3. Add composite indexes for those query patterns.
4. Re-run this audit → client-gap count should approach 0 (only true server-only remain unruled).
Owner: single-agent claim on `firestore.rules` + `firestore.indexes.json` in `AGENT_LANES.md` (no concurrent editor).
