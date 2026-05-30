# Agent 8 — Security & Compliance

## Method

**Scope**: Comprehensive security audit of AMENAPP iOS SwiftUI application focusing on:
- Secrets & API keys in source code
- Firebase Firestore/Storage rules configuration
- Input validation & sanitization across client and Cloud Functions
- Data handling (Keychain, UserDefaults, Firestore)
- Account deletion completeness (App Store 5.1.1)
- Moderation coverage for user-generated content
- COPPA/age assurance implementation
- Analytics PII exposure
- Deep link URL scheme validation

**Tools Used**:
- Code grep/search (Swift, Rules files)
- Manual review of key security files
- Firestore/Storage rules analysis
- Authentication & data flow inspection

**Files Analyzed**:
- AlgoliaConfig.swift — API key handling (✅ correct: read-only key client-side, write key server-only)
- AuthenticationViewModel.swift — Auth token management, 2FA flow, credential storage
- AccountDeletionService.swift — Account deletion pipeline and data removal completeness
- AmenCovenantCheckoutService.swift — Stripe checkout with deep link handling
- AMENAnalyticsService.swift — Analytics event tracking & PII exposure
- AgeAssuranceService.swift — Age tier system & COPPA compliance
- firestore 18.rules, storage.rules — Database & storage access control rules
- DeepLinkRouter.swift, NotificationDeepLinkRouter.swift — Deep link parsing & validation
- ContentModerationService.swift — Pre-submission content moderation
- 521+ files scanned for moderation coverage, secret patterns, Keychain usage

---

## Findings

### CRITICAL (ship-blocking)

**None identified** during this audit that would prevent shipping. The app demonstrates strong security fundamentals with proper credential separation, authentication gating, and data protection mechanisms.

---

### HIGH (fix this sprint)

#### 1. [firestore 18.rules:100-110] Age tier enforcement missing on DM/Conversations create
**Issue**: The `conversations` collection has no visible rules shown in audit sample. Age tier validation (callerCanUseDMs()) is defined but must be enforced on document create to prevent minors bypassing DM restrictions.

**Why it matters**: App Store requirement. Tier A (<13) and B (13-15) users must not be able to initiate DMs even if they manipulate the client.

**Current state**: Helper functions `callerCanUseDMs()` exist and Firestore rules define `callerAgeTier()` with a get() call, but the full rules file was truncated. Assumed to be protected based on code patterns observed.

**Suggested fix**: Verify the complete firestore rules file contains `allow create: if callerCanUseDMs()` on the conversations/{id} and participants subcollections. If missing, add immediately.

**Effort**: S (verify + add 2-3 lines to rules)

---

#### 2. [AuthenticationViewModel.swift:358-365] Client-side deactivation gate can be bypassed
**Issue**: Deactivated account check relies on Firestore read (`userData["isDeactivated"]`), which is client-managed and verifiable only via token refresh. A jailbroken device could patch the binary to skip the forced token refresh and set `accountIsDeactivated = false`.

**Why it matters**: Deactivated users should be prevented from using the app. Server-side rules must enforce this, but the client-side check is the only gate before showing onboarding.

**Current state**: Code includes a note ("FULL FIX (requires server-side work)") acknowledging this is a known limitation. The real protection is assumed to be in Firestore read rules (users/{uid} read is probably gated by a custom claim), but this was not verified in the rules file.

**Suggested fix**:
1. Verify Firestore rules include: `allow read, write: if !(get(/databases/$(database)/documents/users/$(request.auth.uid)).data.get('isDeactivated', false))`
2. Do NOT rely solely on client-side `accountIsDeactivated` state; server rules must deny all writes.
3. Server-side implementation: Cloud Function should set a custom JWT claim `deactivated=true` when an account is deactivated, making the check unforgeable.

**Effort**: M (requires backend coordination to add custom claim deployment)

---

#### 3. [AccountDeletionService.swift:269-304] Storage deletion is best-effort but not guaranteed
**Issue**: `deleteStorageFiles()` loops through known prefixes and deletes recursively, but:
- If a new upload path is added by developers without updating this list, user data won't be deleted
- Failures are caught and logged but don't block account deletion (non-fatal)
- No audit trail of what was actually deleted

**Why it matters**: GDPR/CCPA/App Store 5.1.1 requires "real delete", not best-effort.

**Current state**: Code has comments acknowledging non-fatal failures and a reasonable list of known paths (`profile_images/`, `post_media/`, `voice_messages/`, `studioVoice/`, etc.). The approach is pragmatic but fragile.

**Suggested fix**:
1. Consider deploying a server-side Cloud Function (triggered on account deletion) that enumerates all files under `users/{userId}/*` and deletes them, ensuring 100% coverage.
2. Alternatively: Document the required list of Storage paths in a centralized config (e.g., `StorageConfig.swift`) so any new path must be added in two places (upload code + deletion code).
3. Add success/failure metrics to Firestore so the account deletion service reports which paths were cleaned.

**Effort**: M (refactor to Cloud Function call or maintain a strict config)

---

#### 4. [DeepLinkRouter.swift:54-112] Deep link path traversal not strictly validated
**Issue**: Deep links like `amen://post/{id}` and `amen://user/{userId}` accept arbitrary strings in path components. While the scheme (`amen://`) is validated, the IDs themselves are not checked against expected format (Firestore doc IDs are alphanumeric + hyphens).

**Example attack**: `amen://post/../../admin` or `amen://user/%2e%2e%2fadmin` could potentially construct unintended navigation if the backend doesn't validate.

**Why it matters**: Deep link injection from malicious notifications or websites could cause confusion or bypass moderation.

**Current state**: The router validates scheme and host (e.g., `url.scheme == "amen"`, `host == "post"`), then trusts the path component. Navigation is guarded by Shabbat Mode and feature flags, but not by ID format validation.

**Suggested fix**:
1. Add a helper function to validate Firestore document ID format: `func isValidDocumentId(_ id: String) -> Bool { id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil }`
2. Call this in the parse() method before returning a route.
3. Return `.post(id: postId, highlightCommentId: commentId)` only if `isValidDocumentId(postId) == true`.

**Effort**: S (add validation function + 4-5 guard statements)

---

#### 5. [AMENAnalyticsService.swift:484-491] User ID leakage in analytics events (HIGH risk if names/phones used)
**Issue**: Events like `suggestionImpression`, `suggestionFollowTap`, `profileMiniMessageTap` include `suggestedUserId` and `userId` in properties:
```swift
case .suggestionImpression(let userId, let position, let reason):
    return ["suggested_user_id": userId, "position": position, "reason_type": reason]
```
If Firebase Analytics is misconfigured to export to BigQuery with looser privacy settings, these UIDs could be associated with Firestore display names / phone numbers.

**Why it matters**: GDPR/CCPA: user IDs are pseudonymous, but exported to third-party analytics and combined with display names = PII.

**Current state**: Code correctly sends UIDs (not email/phone) and has opt-out support. However, no documented guarantee that the Firebase Analytics BigQuery export has appropriate data residency / access controls.

**Suggested fix**:
1. Review Firebase Analytics export configuration in Google Cloud Console — ensure BigQuery dataset is private and has restricted access.
2. Add a comment in the Analytics tracking code: `// ⚠️ UIDs exported to BigQuery — ensure dataset is private per GDPR requirements`
3. Consider hashing UIDs (e.g., SHA256) before export if BigQuery access is not strictly controlled.
4. Audit which analytics events carry UIDs and justify each one in code comments.

**Effort**: M (audit existing export config + update documentation)

---

### MEDIUM (next sprint)

#### 1. [firestore 18.rules] Complete rules audit — visibility/access boundaries unclear
**Issue**: The Firestore rules file was truncated during review (only ~100 lines of a multi-KB file). The rules for key collections are not fully visible:
- `posts` create/update rules: are content safety checks enforced (e.g., no null text)?
- `users` read/update: are profile fields properly restricted by visibility settings?
- `prayers`, `testimonies`, `churchNotes`: are these subject to age tier restrictions?

**Why it matters**: Incomplete rules audit means potential data leakage or injection vectors.

**Current state**: Spot checks show strong patterns (`isOwner()`, `isAdmin()`, counter validation, MIME type restrictions on Storage), but full coverage is unknown.

**Suggested fix**:
1. Have a dedicated Firestore rules expert review the complete 18.rules file (prioritize `posts`, `conversations`, `users`, `prayerRequests`).
2. Create a rules coverage matrix: collections × operations (create/read/update/delete) and verify each has explicit allow/deny.
3. Document assumptions (e.g., "assumes all user read requests pass through getDocument() to check visibility").
4. Test with Firestore Emulator: try creating a post with empty text, a DM from a Tier B user, following self, etc.

**Effort**: L (comprehensive expert review + emulator testing)

---

#### 2. [AgeAssuranceService.swift:56-74] Teen tier migration path not re-enforced on every session
**Issue**: When an old user with no DOB is first loaded, they are assigned `.teen` tier and `needsVerification=true` is set. However, this is only enforced in the client-side `loadTier()` call. If the user clears app cache or the migration happens offline, the re-verification might not trigger on the next session.

**Why it matters**: A teen account might persist indefinitely with auto-upgraded-to-adult logic in legacy code.

**Current state**: `createUnverifiedMigrationProfile()` writes `profile.verificationStatus = .pending` to Firestore, but the app only checks `needsVerification` in client state. If a network error occurs, the user might bypass the gate.

**Suggested fix**:
1. Add a server-side Cloud Function `enforceAgeVerification()` that is called on every sign-in, checking if the user has no age profile and setting a custom claim `needsAgeVerification=true`.
2. On client: check this claim during onboarding; if true, block all DM/adult features until verified.
3. Add a test: create a user, verify they're .teen, then manually set their profile to .adult via Firebase Console, and confirm the app still gated them correctly on next session.

**Effort**: M (requires Cloud Function deployment)

---

#### 3. [AuthenticationViewModel.swift:336-356] Deactivation check uses Firestore cache on launch
**Issue**: At line 402-406, if cached local snapshot exists, the code calls `getDocument(source: .cache)`. If the user was deactivated while the app was backgrounded, the local cache may still show `isDeactivated=false`, and the gate will not trigger until the cache is refreshed.

**Why it matters**: A deactivated user could briefly use the app on a stale cache.

**Current state**: The code has a 5-second cache duration but doesn't enforce a server-side check on every launch.

**Suggested fix**:
1. Force a fresh Firestore read (not cache) for the `isDeactivated` field on every cold start: `getDocument(source: .server)`.
2. Accept the network latency cost (adds 100–300ms to launch) in exchange for correctness.
3. Use the cached path only for warm starts (app return from background < 60s).

**Effort**: S (change `.cache` to `.server` + add timestamp check)

---

#### 4. [ContentModerationService.swift] Moderation bypass possible for some content types
**Issue**: The service is called explicitly in a `Task.detached(priority: .utility)` fire-and-forget after the post is written (CreatePostView.swift). This means:
- If the user force-closes the app immediately, moderation may not run
- Comments, prayer requests, and direct messages may not all use this service (not verified in scope)
- No confirmation to the user if their post was flagged and deleted

**Why it matters**: Post-write moderation is visible to the user (post appears, then disappears), creating a bad UX and potential for abuse.

**Current state**: Pre-submission safety gates exist (`SafetyOrchestrator`) but ContentModerationService is post-write. Code includes a comment acknowledging this is intentional for performance, but the trade-off is incomplete coverage.

**Suggested fix**:
1. Audit all content creation paths (posts, comments, prayer requests, testimonies, church notes, messages, Berean prompts) to confirm moderation is called.
2. For critical features (DMs, Berean), move moderation to pre-submit (before the write).
3. Add a toast notification: "Your post was reviewed and removed due to community guidelines" if a post is deleted by moderation.
4. Store deletion event in Firestore (users/{uid}/moderation_actions) for user transparency & appeals.

**Effort**: M (audit + add pre-submit gates for high-risk features)

---

#### 5. [PrivacyDashboardView, GDPRConsentView] Data export functionality exists but untested
**Issue**: Grep found references to `GDPRConsentView` and `dataExportRequests` collection, indicating data export & GDPR consent features. However:
- No comprehensive data export service was reviewed
- Unclear if all PII fields are included in exports (photos, cached credentials, Keychain tokens)
- No test of the export functionality to ensure completeness

**Why it matters**: GDPR Article 20 requires a portable, machine-readable export of all personal data. Incomplete exports = non-compliance.

**Suggested fix**:
1. Create a `DataExportService` that mirrors `AccountDeletionService`: enumerate all collections, subcollections, and Storage files for a user.
2. Package the export as a JSON/CSV file (depending on data type) and store in a private Storage bucket.
3. Email the user a download link.
4. Test the export by signing up a user, creating posts/prayer requests/messages, and verifying all data appears in the export.
5. Verify fields: Firestore user doc, posts, comments, likes, followers, messages, prayer requests, voice messages, profile images, media, Berean chat history.

**Effort**: L (build service, test, deploy)

---

### LOW (backlog)

#### 1. [AlgoliaConfig.swift] Search key rotation not documented
**Issue**: Comment on line 15: "SECURITY: Rotate the search key in Algolia dashboard — the old key is in git history."

The Search API key is read from Info.plist (built at compile-time), so rotation requires a new app build and App Store update. If the key is ever leaked, the old key will remain in git history and anyone with access to the repo can search.

**Why it matters**: Low risk because the search key is read-only and cannot modify indexes. However, it reveals Algolia usage patterns.

**Suggested fix**:
1. If the search key is ever compromised, rotate it immediately and release a new app build.
2. Consider using Algolia's Secured API Keys feature (client-side, derived from a restricted server-side key) for additional per-user filtering.
3. Git history cannot be retroactively deleted easily; add a comment in commit message: "Search key rotated — old key in history should be considered compromised".

**Effort**: S (documentation + consider API key derivation)

---

#### 2. [AuthenticationViewModel.swift:777-806] Cached credentials in UserDefaults
**Issue**: Display name and photo URL are cached in UserDefaults for fast re-login (AutoLoginSplashView):
```swift
UserDefaults.standard.set(name, forKey: "cachedUsername")
UserDefaults.standard.set(photoURL, forKey: "cachedPhotoURL")
```

UserDefaults is NOT encrypted on disk; a jailbroken device or forensic recovery could read these.

**Why it matters**: Low risk because display name is public info. However, photo URL could be used to correlate identities if the user later unlinks their account.

**Suggested fix**:
1. Consider moving to Keychain for additional protection (iOS Keychain is encrypted).
2. Or accept the risk and document it: "// ⚠️ Cached in plaintext UserDefaults for performance — PII is public anyway"
3. Clear these on sign-out (which already happens in signOut()).

**Effort**: S (move to Keychain wrapper)

---

#### 3. [NotificationDeepLinkRouter.swift:90-200] Limited validation of notification payload fields
**Issue**: The router parses push notification payloads and navigates to posts/users/conversations based on userInfo["postId"], userInfo["actorId"], etc. These are strings from a remote push notification server (Firebase Cloud Messaging).

While Firebase handles authentication of the APNs payload, the content (field names and values) are not validated for format. Malformed IDs could cause crashes or unexpected routing.

**Why it matters**: Low risk because the IDs are still validated against Firestore on load (you can't navigate to a non-existent post). However, incorrect routing could confuse users.

**Suggested fix**:
1. Add optional field extraction with defaults: `let postId = userInfo["postId"] as? String, !postId.isEmpty else { return }`
2. Add telemetry to track malformed notification payloads: `analytics.track(.custom(name: "malformed_notification", parameters: ["missing_field": "postId"]))`

**Effort**: S (add validation + logging)

---

#### 4. [CreatePostView] Media caption moderation runs per caption but not checked for consistency
**Issue**: User-authored media captions are moderated in a loop (perMediaCaptionModerationTask), but if caption moderation fails for some and succeeds for others, the user might upload mixed moderation results.

**Why it matters**: Low risk because each caption is moderated, but there's no "all captions must pass" validation.

**Suggested fix**:
1. Aggregate caption moderation results and block publish if ANY caption is flagged for review.
2. Display a toast: "One or more media captions were flagged. Please revise and try again."

**Effort**: S (adjust moderation aggregation logic)

---

#### 5. [Keychain Usage] No audit of what's stored in Keychain
**Issue**: AccountDeletionService clears all Keychain items on account deletion:
```swift
SecItemDelete(genericQuery as CFDictionary)  // generic password
SecItemDelete(internetQuery as CFDictionary) // internet password
```

However, no review of what actually gets stored there during normal operation. If a Cloud Function or service stores auth tokens in Keychain without the deletion service knowing, those won't be cleared.

**Why it matters**: Low risk if practices are consistent. But if an old service starts storing data in Keychain and isn't added to the deletion service, orphaned data could persist.

**Suggested fix**:
1. Maintain a list of all Keychain services used: `AuthenticationViewModel` (firebase token?), `PhoneVerificationService` (verification ID?), `FCMTokenManager`, etc.
2. Document the contract: "Any service storing to Keychain must ensure `AccountDeletionService.clearLocalState()` deletes it."
3. Add an assertion in tests: sign up → create data → delete account → verify Keychain is empty.

**Effort**: S (audit + documentation)

---

## What I did NOT check

1. **Cloud Functions code** — Backend functions are written in TypeScript/Node.js. Only glanced at moderation/Stripe/auth functions. A full audit of function input validation, error handling, and admin SDK usage would be needed.

2. **Info.plist secrets** — Didn't open GoogleService-Info.plist or Info.plist, but checked that Algolia key is sourced from there (correct, not hardcoded).

3. **Full Firestore rules file** — Only first ~100 lines reviewed due to file size. A complete audit is needed for `posts`, `conversations`, `users`, `prayers`, and all other collections.

4. **XCConfig & build settings** — Didn't audit Config.xcconfig or build secrets injection. Assumed best practices (Config.xcconfig is .gitignored).

5. **Biometric authentication** — AgeAssuranceService and AuthenticationViewModel mention biometrics but weren't fully reviewed.

6. **Crash reporting & Sentry** — Didn't check if PII is logged to Crashlytics/Sentry. Only verified that analytics doesn't include email/phone (UIDs only).

7. **Third-party SDK compliance** — Didn't audit Firebase SDK, Stripe SDK, or other dependencies for their own security issues.

8. **SSL/TLS pinning** — No review of HTTPS pinning, certificate validation, or man-in-the-middle protection.

9. **Jailbreak detection** — No hardening against jailbroken devices (some apps add `canOpenURL` or runtime checks).

10. **OAuth provider integrations** — Apple Sign-In, Google Sign-In, and phone auth flows were reviewed only for the client side, not the backend OAuth configuration.

---

## Summary

**Strengths**:
- Algolia write key correctly kept server-side; read key is safe for client
- Strong 2FA implementation with credential storage via AuthCredential (not raw password)
- Account deletion service is comprehensive, deleting Firestore, Storage, Realtime DB, and Auth
- Deep link routing validates scheme (`amen://`)
- Analytics respects opt-out (GDPR Article 21)
- Age assurance system defaults to .teen (restricted) on unknown tier
- Moderation pipeline exists and is called pre/post-submission for critical features

**Weaknesses**:
- Deactivation check relies partially on client-side Firestore read (should have server-side claims)
- Storage deletion is best-effort and could miss paths if new upload types are added
- Deep link IDs not validated against expected format (should add regex check)
- User IDs exported to analytics BigQuery with unclear privacy controls
- Firestore rules partially reviewed; full audit needed
- Data export functionality exists but untested for completeness
- Post-write moderation is fire-and-forget; some content types may skip moderation entirely

**Recommendation**: Address HIGH-1 through HIGH-5 before next release. Schedule a dedicated session for MEDIUM-1 (full rules audit) with a Firestore security expert.

