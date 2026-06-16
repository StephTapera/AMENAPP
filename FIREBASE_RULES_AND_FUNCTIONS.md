# Firebase Rules + Functions Audit
Generated: 2026-06-16 | Branch: app-store-readiness-overnight
Firebase Project: amen-5e359 | Functions Runtime: node22

---

## Firestore Rules Assessment

**File:** `firestore.rules` (3388 lines)

### Global Architecture

| Check | Status | Notes |
|---|---|---|
| Default-deny catch-all | PASS | Lines 3386-3388: `match /{document=**} { allow read, write: if false; }` — all unlisted collections fail closed |
| isSignedIn() helper | PASS | Line 4: `return request.auth != null` — used consistently |
| isOwner(uid) helper | PASS | Line 5: `return isSignedIn() && request.auth.uid == uid` |
| isAdminSDK() helper | PASS | Line 6: checks `request.auth.token.get('admin', false) == true` |
| premiumFieldsUnchanged() | PASS | Line 327: blocks client writes to premiumTier, hasPlusAccess, hasProAccess, aiUsageRemaining |
| ageTierUnchanged() | PASS | Line 334: blocks client writes to ageTier, ageCategory, dateOfBirth, ageVerified, isMinor |
| roleAndSafetyFieldsUnchanged() | PASS | Line 345: blocks client writes to isAdmin, role, trustScore, accountStatus, fcmToken |
| hasRawPII() guard | PASS | Blocks writes of contactPhone, contactEmail, homeAddress to root user document |

### Per-Collection Status

| Collection | Read Rule | Write Rule | Risk | FIRE-ID |
|---|---|---|---|---|
| `/users/{userId}` | Any signed-in user | Owner only (guarded field checks) | MED — all signed-in users can read any profile; defense-in-depth gap if PII accidentally written to root doc | FIRE-003 |
| `/users/{userId}/private/age_assurance` | Owner only | Owner only | LOW | FIRE-002 |
| `/conversations/{convId}` | Participants only + non-blocked | Participants only | LOW — correctly private | FIRE-004 |
| `/conversations/{convId}/messages` | Participants + non-blocked | Participants only | LOW | FIRE-004 |
| `/moderationQueue` | Moderator/pastor/owner/executive_admin | CF-write field allowlist for user creates; CF-only for escalateImmediately | LOW | FIRE-005 |
| `/auditLog` | Owner/executive_admin only | CF-only | LOW | FIRE-005 |
| `/userReports` | Reporter or moderator/executive_admin | CF-only | LOW | FIRE-006 |
| `/prayerOS/{uid}/cards` | Owner only | Owner only (rate-limited field check) | MED — prayer detail stored unencrypted | FIRE-023 |
| `/safetyAuditLog` | Admin SDK only | Signed-in user creates (field allowlist) | MED — **DUPLICATE RULE** second block at ~line 3195 sets write: if false; first block wins but creates maintenance confusion | FIRE-008 |
| `/testimonies/{id}` | `resource.data.visibility == 'published'` — NO isSignedIn() guard | `if false` | MED — publicly readable by unauthenticated clients; T&S policy decision required | FIRE-009 |
| `/ncmecReports` | `if false` | `if false` | LOW — correctly server-only | FIRE-024 |
| `/ncmecSubmissionQueue` | `if false` | `if false` | LOW | FIRE-024 |
| `/mandatory_reports` | `if false` | `if false` | LOW | FIRE-024 |
| `/legalHolds` | legalReviewer custom claim only | `if false` | LOW | FIRE-024 |

### Recommended Fixes (not yet deployed)

1. **FIRE-008:** Remove the duplicate `/safetyAuditLog` block in the Global Resilience section (~line 3195). Keep only the block at ~line 2982. Add comment: `// This rule supersedes the GR section block. Client creates allowed with field allowlist.`

2. **FIRE-009:** Add `isSignedIn() &&` to the testimonies read rule if unauthenticated reads are not intended. This requires a T&S Lead decision (OPEN-5 policy).

3. **FIRE-003:** Consider tightening `/users/{uid}` read to owner-only for sensitive profile fields, or explicitly enumerate safe fields. Low priority — no PII confirmed in root doc currently.

---

## Storage Rules Assessment

**File:** `storage.rules` (735 lines)

### Global Architecture

| Check | Status | Notes |
|---|---|---|
| Default-deny catch-all | PASS | Lines 733-735: `match /{allPaths=**} { allow read, write: if false; }` |
| isOwner(uid) helper | PASS | `request.auth.uid == uid` — path wildcard UID comparison |
| withinVideoLimit() | PASS | `request.resource.size <= 100 * 1024 * 1024` (100 MB) |
| Cross-user overwrite prevention | PASS | All write rules gate on isOwner(uid) where uid is from path wildcard | FIRE-019 |

### Per-Path Status

| Path | Read Rule | Write Rule | Risk | Storage-ID |
|---|---|---|---|---|
| `uploads/quarantine/{uid}/...` | Owner only | Owner create-only (no update) | LOW — evidence substitution prevented | FIRE-019 |
| `uploads/approved/{uid}/{mediaId}` | `if true` — PUBLIC no auth | Owner only | MED — approved content publicly accessible to unauthenticated clients; intended for CDN delivery but explicit policy needed | FIRE-020 |
| `profile_photos/{uid}/{photoId}` | Owner only (quarantine path) | Owner only | LOW | |
| `profilePhotos/{uid}/{photoId}` | Any signed-in user | Owner only | LOW | FIRE-021 |
| `profile_images/{uid}/{filename}` | Owner only | Owner only | LOW — third overlapping path, maintenance risk | FIRE-021 |
| `churchNotes/{uid}/{noteId}/audio` | Owner only | Owner only + isAudioType() (deprecated regex) | MED — deprecated regex helper still in use | FIRE-022 |
| `churchNotes/{uid}/{noteId}/images` | Owner only | Owner only + isImageType() (deprecated) | MED | FIRE-022 |
| `churchNotes/{uid}/{noteId}/video` | Owner only | Owner only + isVideoType() (deprecated) | MED | FIRE-022 |
| `voice_messages/{uid}/...` | Owner only | Owner only + isAllowedAudioType() (new helper) | LOW |
| `liveRoom/...` | Participants only | Owner only | LOW |

### Recommended Fixes (not yet deployed)

1. **FIRE-022:** Replace `isAudioType()`, `isImageType()`, `isVideoType()` with `isAllowedAudioType()`, `isAllowedImageType()`, `isAllowedVideoType()` on the three `churchNotes/{uid}/{noteId}/...` paths (lines 425-441). Then remove the deprecated helpers (lines 101-111). This closes a crafted content-type bypass vector.

2. **FIRE-020:** Policy decision required: add `isSignedIn() &&` to `uploads/approved` read rule if app requires auth to view any media, or document the public CDN delivery intent explicitly in rules comments.

3. **FIRE-021:** After the quarantine pipeline is fully deployed, consolidate the three profile photo paths to a single canonical path. Until then, add a comment to each path mapping the iOS file that writes to it.

---

## Functions Inventory

### Backend/functions/src/ (Creator codebase — deploy with `firebase deploy --only functions:creator:...`)

| Function Name | Trigger | Gen | Region | Auth Required? | App Check? | Payload Validation? | Rate Limited? | Deploy Status |
|---|---|---|---|---|---|---|---|---|
| bereanChat | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES (rateLimit.ts) | DEPLOYED |
| bereanSuggest | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| bereanConstitutionalReview | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| socialGraph_follow | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| socialGraph_unfollow | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayer_createCard | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayer_listCards | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayer_updateCard | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| accountSuspension_suspend | HTTPS Callable | Gen-2 | us-east1 | YES (admin token) | YES | YES | YES | DEPLOYED |
| accountSuspension_restore | HTTPS Callable | Gen-2 | us-east1 | YES (admin token) | YES | YES | YES | DEPLOYED |
| evaluateSabbathMode | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| affiliateTierHelper | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| askCreatorQuery | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| topicClusterEngine | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| manualEntry | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| googleBooksProvider | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| substackMediumProvider | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| youtubeProvider | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |
| catalogSearch | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | UNDEPLOYED (new file) |

### functions/src/ (Default codebase — deploy with `firebase deploy --only functions:default:...`)

| Function Name | Trigger | Gen | Region | Auth Required? | App Check? | Payload Validation? | Rate Limited? | Deploy Status |
|---|---|---|---|---|---|---|---|---|
| capabilityRegistry_list | HTTPS Callable | Gen-2 | us-east1 | YES | NO (documented — must work before App Check) | YES | NO | DEPLOYED |
| contextEngine_getGrants | HTTPS Callable | Gen-2 | us-east1 | YES | NO (documented) | YES | NO | DEPLOYED |
| contextEngine_getAuditLog | HTTPS Callable | Gen-2 | us-east1 | YES | NO (documented) | YES | NO | DEPLOYED |
| scripture_detectReferences | HTTPS Callable | Gen-2 | us-east1 | YES | NO (free/fast) | YES | NO | DEPLOYED |
| scripture_searchVerses | HTTPS Callable | Gen-2 | us-east1 | YES | NO | YES | NO — DoS risk FIRE-025 | DEPLOYED |
| scripture_getVerses | HTTPS Callable | Gen-2 | us-east1 | YES | NO | YES | NO | DEPLOYED |
| prayerOS_createCard | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayerOS_listCards | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayerOS_updateCard | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| prayerOS_deleteCard | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | YES | DEPLOYED |
| bereanIsland_trigger | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | NO | DEPLOYED |
| writeWithBerean_assist | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | NO | DEPLOYED |
| sermonCompanion_session | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | NO | DEPLOYED |
| createSpaceTier | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | NO | DEPLOYED — but has FIRE-010 auth bug |
| visitVerification_confirm | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | DEPLOYED |
| noteGive_process | HTTPS Callable | Gen-2 | us-east1 | YES | YES | YES | UNKNOWN | DEPLOYED |
| dailyVerse_fetch | Scheduled (daily) | Gen-2 | us-east1 | N/A | N/A | N/A | N/A | DEPLOYED |
| ncmecReporter | Firestore trigger | Gen-1 | us-central1 | N/A | N/A | YES | N/A | DEPLOYED |

### Key Security Observations

1. **FIRE-010 — createSpaceTier auth gap:** After verifying the caller is authenticated, the function does NOT verify the caller is the owner or admin of the target spaceId. Any authenticated user can insert a paid tier on any Space. Fix: read `spaces/{spaceId}`, check `doc.data().leaderId === request.auth.uid`, throw `permission-denied` if not. Deploy to us-east1.

2. **FIRE-013 — enforceAppCheck: false on 5 callables:** capabilityRegistry_list, contextEngine_getGrants, contextEngine_getAuditLog, scripture_detectReferences, scripture_searchVerses all set enforceAppCheck: false. Auth is still required. Recommendation: add rate limiting from rateLimit.ts on these endpoints.

3. **FIRE-016 — Rate limiting gap in functions/src:** The rateLimit.ts utility in Backend/functions/src is not imported by functions/src callables. scripture_getVerses (calls external API.Bible per invocation), bereanIsland_trigger, writeWithBerean_assist, and sermonCompanion_session have no per-user call limits.

4. **FIRE-015 — No PII in Cloud Logging (PASS):** All callable functions examined log only uid, category, cardId, and status — never prayer text, message body, or personal content. Correctly implemented.

5. **FIRE-011 — No data.uid as identity (PASS):** All callables use request.auth.uid or request.auth?.uid as caller identity. data.uid is only used as a target (subject) with additional admin token verification.

---

## Emulator Test Status

**UNVERIFIED — human must run:**

```bash
# From repo root only. Never from a subdirectory.
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase emulators:exec \
  --project amen-5e359 \
  --only firestore,functions,storage \
  "cd Backend/functions && npm test && cd ../../functions && npm test"
```

Known test files in repo:
- `Backend/rules-tests/distinctives.rules.test.ts` — Firestore rules tests for creator codebase
- Various `*.test.ts` files in `Backend/functions/src/` and `functions/src/`

---

## Staged-But-Not-Deployed Items

The following new Cloud Function source files exist in the repo but have NOT been deployed:

| File | Function(s) | Codebase | Suggested Region | Notes |
|---|---|---|---|---|
| `Backend/functions/src/billing/affiliateTierHelper.ts` | affiliateTierHelper | creator | us-east1 (quota) | New billing function |
| `Backend/functions/src/ai-catalog/askCreatorQuery.ts` | askCreatorQuery | creator | us-east1 | New AI catalog function |
| `Backend/functions/src/ai-catalog/topicClusterEngine.ts` | topicClusterEngine | creator | us-east1 | New AI catalog function |
| `Backend/functions/src/ingestion/manualEntry.ts` | manualEntry | creator | us-east1 | New ingestion function |
| `Backend/functions/src/ingestion/providers/googleBooksProvider.ts` | googleBooksProvider | creator | us-east1 | New provider |
| `Backend/functions/src/ingestion/providers/substackMediumProvider.ts` | substackMediumProvider | creator | us-east1 | New provider |
| `Backend/functions/src/ingestion/providers/youtubeProvider.ts` | youtubeProvider | creator | us-east1 | New provider |
| `Backend/functions/src/search/catalogSearch.ts` | catalogSearch | creator | us-east1 | New search function |
| `Backend/functions/src/selahConnection 2.ts` | (unknown) | creator | us-east1 | Filename has space — requires rename before deploy |
| `AMENAPP/AMENAPP/Features/Bridges/NoteGive/` | n/a (Swift files) | iOS | N/A | New iOS bridge files; not in pbxproj |
| `AMENAPP/AMENAPP/Features/Bridges/VerseResonance/DailyVerseCard.swift` | n/a | iOS | N/A | New Swift file; verify target membership |
| `AMENAPP/AMENAPP/Features/Bridges/Visits/VisitVerificationService.swift` | n/a | iOS | N/A | New Swift file; verify target membership |

**CRITICAL NOTE:** `selahConnection 2.ts` contains a space in the filename. This will cause issues with Firebase CLI deploy. Rename to `selahConnection.ts` or `selahConnectionV2.ts` before deploying.

**Quota note:** us-central1 is at ~999-1000/1000 services. ALL new functions must be deployed to us-east1. Add each to the Interim Region Table in `docs/FUNCTION_INVENTORY.md`. See DEPLOY_PLAN.md.
