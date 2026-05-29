# Security & Secrets Audit
**Date:** 2026-05-28  
**Branch:** audit/2026-05-28  
**Auditor:** Claude Code (claude-sonnet-4-6)

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `AMENAPP/GoogleService-Info.plist:10` | **Blocker** | Hardcoded secret / git-tracked | Firebase API key `AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k` is committed to git history (3 commits: `01adf60`, `9b347e4`, `ac04a31`) even though the file is now `.gitignore`-listed. The key is still in git history and must be rotated. |
| `AMENAPP/AlgoliaConfig.swift:15,20` | **Blocker** | Hardcoded secret / git-tracked | Algolia `applicationID = "182SCN7O9S"` and `searchAPIKey = "8727f5af5779e9795b12b565bba20dc3"` are hard-coded in Swift source and tracked in git history (first appeared in commit `d27ce7a`). The search key is described as "safe for client apps" but it is still a real credential tied to a paid account — leaking it enables hotlinking of search capacity. Application ID is always public; the search key should be sourced from `Config.xcconfig` / Remote Config instead of compiled in. |
| `AMENAPP/AMENMediaService.swift:21-22` | **High** | Client-side secret | `SPOTIFY_CLIENT_SECRET` is read from `Info.plist` (via `Config.xcconfig`) at runtime and used to obtain a Spotify OAuth access token directly from the client (`fetchSpotifyToken`). The client secret is then embedded in the app binary / plist and is trivially extractable with `strings`. Spotify OAuth client-credential flows must run server-side. |
| `AMENAPP/AMENMediaService.swift:14-15` | **High** | Client-side secret | `YOUTUBE_API_KEY` is read from `Info.plist` and embedded in Google API requests directly from the client. YouTube keys must be restricted by bundle ID in GCP Console and ideally proxied server-side. |
| `Info.plist:67-68` (+ `AMENMediaService.swift`) | **High** | Client-side secret in plist | `SPOTIFY_CLIENT_SECRET` is mapped in `Info.plist` as `$(SPOTIFY_CLIENT_SECRET)`. Any app binary can be unzipped and the `.plist` read with `plutil`, exposing the secret. This is a structural issue: OAuth client secrets must never live in `Info.plist`. |
| `AMENAPP/CharityNavigatorService.swift:50` | **High** | Placeholder / unresolved secret | `private let apiKey = "YOUR_CHARITY_NAVIGATOR_API_KEY"` — a placeholder string is compiled into the binary. The service is no-op guarded (`guard apiKey != "YOUR_CHARITY_NAVIGATOR_API_KEY" else { return }`), but the pattern is fragile and should be removed or properly sourced. |
| `AMENAPP/ClaudeService.swift:246` | **Med** | PII logging | `dlog("   User email: \(currentUser?.email ?? "none")")` — logs the authenticated user's email address on every auth-error code path in the Berean proxy. Although `dlog` is a DEBUG-only no-op in Release builds (verified: `DebugLog.swift:22`), this pattern leaks PII to Xcode consoles and any debugging harness. |
| `AMENAPP/AMENAPPApp.swift:743` | **Med** | PII logging | `dlog("   Email: \(authResult.user.email ?? "none")")` — logs user email on successful email-link sign-in. Same DEBUG-only caveat applies; still a habit to break. |
| `AMENAPP/SignInView.swift:1385` | **Med** | PII logging | `dlog("📧 Email: \(appleIDCredential.email ?? "none")")` — logs Apple-provided email on Apple Sign-In. Email is only returned on first sign-in and may be the real address, not the relay. |
| `AMENAPP/FirebaseManager.swift:276` | **Med** | PII logging | `dlog("✅ FirebaseManager: Verification email sent to \(user.email ?? "unknown")")` — logs user email on every verification-email send. |
| `AMENAPP/ProfileView.swift:666,794,883,886,1211,1214,1217,1220,2829,2890` | **Med** | Content logging | Multiple `dlog()` calls output post/comment content prefixes (`.prefix(50)`). In DEBUG builds this streams user-generated content to Xcode console. Not a Release issue, but content includes potentially sensitive prayer requests and testimony text. |
| `AMENAPP/SafetyPlanStore.swift:43-54` | **Med** | Sensitive data in UserDefaults | The user's interactive safety plan (warning signs, coping strategies, trusted people to call, professional contacts) is stored in `UserDefaults.standard` under key `"amen.safetyPlan"`. `UserDefaults` is not encrypted and is included in unencrypted iTunes/iCloud backups unless explicitly excluded. Health-adjacent crisis data should be stored in the iOS Keychain or in a `NSFileProtectionComplete`-protected file. |
| `AMENAPP/TrustedContactPicker.swift:37-47` | **Med** | Sensitive data in UserDefaults | Trusted contact names and phone numbers are stored in `UserDefaults.standard` under `"amen.trustedContacts"`. Phone numbers are PII; they should be persisted in the Keychain or a protected file. |
| `AMENAPP/BereanChatView.swift:196-216` | **Med** | AI conversation history in UserDefaults | Berean AI conversation message cache is written to `UserDefaults.standard` (key: `berean_msg_cache_<sessionId>`). Conversations can contain sensitive spiritual/personal disclosures. Should use an encrypted store or `NSFileProtectionComplete`. |
| `AMENAPP/BereanDataManager.swift:148` | **Med** | AI saved messages in UserDefaults | Saved Berean messages stored in `UserDefaults.standard` under `"berean_saved_messages"`. Same concern as above. |
| `AMENAPP/BereanAIAssistantView.swift:4943` | **Med** | AI conversation history in UserDefaults | Full Berean conversation list stored in `UserDefaults.standard` under `"berean_conversations"`. |
| `AMENAPP/ClaudeService.swift:364` | **Med** | Prompt injection vector | The `systemPromptSuffix` parameter is appended verbatim as `"\n\nAdditional style instruction: \(suffix)"` in `buildSystemPrompt`. This suffix can be passed by callers (including `BereanChatProxyTypes.swift`, `UnifiedChatView.swift`, `SelahScripture/SelahScriptureAIServices.swift`). While jailbreak detection runs on the user *message*, no sanitization runs on the `systemPromptSuffix` string before it is injected into the system prompt. A compromised or malicious call site could inject arbitrary system instructions. |
| `AMENAPP/OpenAIService.swift:488` | **Med** | Prompt injection vector | Same issue in `OpenAIService.buildSystemPrompt`: `"\n\nAdditional style instruction: \(suffix)"` is unsanitized. |
| `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift:105` | **Med** | Direct OpenAI WebSocket connection | `BereanRealtimeWebSocketTransport` opens a WebSocket directly to `wss://api.openai.com/v1/realtime` using a `clientSecret.value` as a Bearer token. This secret is obtained from `BereanVoiceSessionManager → BereanRealtimeSessionManager` via a Cloud Function (`createSession`), which is correct. However the short-lived `clientSecret.value` is held in memory in `activeSecret: BereanRealtimeClientSecret?` (a `@Published` property). Verify the secret is not accidentally logged, serialized to disk, or included in crash reports via Crashlytics. |
| `AMENAPP/SynapticStudioView.swift:190-196` | **Med** | HealthKit biometric data to AI | Heart rate, HRV, and step count from HealthKit are included raw in the Cloud Function payload (`"heart_rate"`, `"hrv"`, `"biometric_context"`). This transmits sensitive health data to a backend AI service. The `Info.plist` `NSHealthShareUsageDescription` states "No health data is stored" — the backend must honour this and must not persist the biometric values in Firestore/logs. Requires server-side verification. |
| `AMENAPP/GoogleService-Info.plist` | **Med** | Firebase API key restrictions | The committed `GoogleService-Info.plist` contains `AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k`. Firebase web/API keys should have application restrictions set to "iOS apps" with the bundle ID `tapera.AMENAPP` in the GCP Console. Without restrictions, the key can be used from any HTTP client to hit Firebase Auth, Firestore, etc. |
| `firestore.rules:588-627` | **Low** | Followers-only post visibility gap | Known caveat documented in rules: posts with `visibility = "Followers"` are not enforced at the Firestore rules layer because the `/follows` subcollection uses auto-generated IDs. Direct document reads bypass the followers-only gate. Mitigation exists (FeedAPIService filtering + `finalizePostPublish` callable), but a determined user can read another user's "Followers"-only posts by document ID. |
| `firestore.rules:605-613` | **Low** | Covenant-gate gap | Posts gated by `covenantId` only check `exists(/covenantSubscriptions/<uid>)` — "has any covenant subscription", not "subscribed to this specific covenant". A user with any subscription can read any covenant-gated post. Documented as known limitation. |
| `AMENAPP/AMENAPPApp.swift:370-372` | **Low** | Deep link scheme check | The `handleChurchNoteDeepLink` function checks `url.scheme == "amenapp" || url.host == "amenapp.com"`. The second condition `url.host == "amenapp.com"` is unreachable here because `.onOpenURL` is only triggered for custom-scheme URLs registered in `CFBundleURLSchemes`; https universal links use a separate AASA/AppDelegate path. The condition is harmless but misleading. |
| `AMENAPP/NotificationDeepLinkRouter.swift:390-406` | **Low** | Deep link host validation | Universal link handling validates `host.hasSuffix("amenapp.com")`. `hasSuffix` is correct but consider using `host == "amenapp.com" || host.hasSuffix(".amenapp.com")` to be explicit that subdomains are also allowed. Currently an attacker cannot register `evilameapp.com` (it doesn't end in amenapp.com), but `attackeramenapp.com` would pass the suffix check. |
| `AMENAPP/AMENAPPApp.swift:388-395` | **Low** | UID logged in production | `dlog("🎬 OnboardingFlowView fullScreenCover check: currentUser=\(Auth.auth().currentUser?.uid ?? "nil")...")` — logs user UID and `hasCompletedOnboarding` flag. DEBUG-only but UID is an internal identifier that should not appear in production logs or crash reports. |

---

## Not Fully Wired / Exposed

### Secrets Found

| Secret | Location | Status |
|--------|----------|--------|
| Firebase API key `AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k` | `AMENAPP/GoogleService-Info.plist` (committed to git) | **Must be rotated** — present in 3 git commits |
| Algolia search key `8727f5af5779e9795b12b565bba20dc3` | `AMENAPP/AlgoliaConfig.swift` (committed to git) | **Should be rotated** — present in git history since `d27ce7a` |
| Algolia App ID `182SCN7O9S` | `AMENAPP/AlgoliaConfig.swift` | Low risk (public), but should be moved to xcconfig |
| `SPOTIFY_CLIENT_SECRET` | `Info.plist` / `AMENMediaService.swift` | **Client-side secret — must be moved to server proxy** |
| `YOUTUBE_API_KEY` | `Info.plist` / `AMENMediaService.swift` | Client-side key — apply GCP bundle-ID restriction; consider proxying |
| `YOUVERSION_API_KEY`, `GOOGLE_VISION_API_KEY`, `VERTEX_AI_KEY` | `Info.plist` template keys | Keys are empty in committed xcconfig; correct. Rotation note exists in `AMENAPP/Config.xcconfig` for former YouVersion exposure. |

### Confirmed Clean

- `CLAUDE_API_KEY` / `OPENAI_API_KEY`: Both confirmed empty in `Config.xcconfig`. All AI calls routed through Firebase Cloud Functions. `ClaudeService.swift` and `OpenAIService.swift` use no on-device key.
- `STRIPE` / `RevenueCat`: No Stripe secret keys found. RevenueCat public key plumbed through xcconfig (empty in committed copy).
- Keychain use: `SecureStorage.load(account: "emailForSignIn")` confirmed for email sign-in link storage (correct).
- Firestore rules: Comprehensive, well-structured. No unauthenticated read paths found. Premium/system fields blocked from client writes. All AI subcollections owner-only.
- Storage rules: Default-deny with owner-only writes per subcollection. Content-type and size enforcement present.

### Insufficient Rules / Gaps

- **Followers-only posts**: Documented gap in `firestore.rules:596-605`. Direct document read bypasses follower filter. Fix: add `users/{authorId}/followers/{followerId}` subcollection and update rule.
- **Covenant gate**: Any subscription holder reads any covenant post. Fix: restructure to `users/{uid}/covenantAccess/{covenantId}` for per-covenant `exists()` check.

### PII / Sensitive Data Persistence

- `SafetyPlanStore` and `TrustedContactStore` write crisis/contact PII to plain `UserDefaults`. On a non-encrypted device or via unencrypted backup, this data is accessible. These are designed "offline-first, privacy-first" features — the trade-off is documented in comments — but the storage tier does not match the sensitivity.
- Berean AI conversation history in `UserDefaults` can include confessional/pastoral content.

---

## Fix Recommendations

### Blocker — Action Required Before Any Public Release

**1. Rotate the Firebase API Key** (`AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k`)
```
GCP Console → APIs & Services → Credentials → API Key "Browser key (auto created by Firebase)"
→ Regenerate (or delete and create a new one, then update GoogleService-Info.plist).
Apply restriction: Application restrictions = iOS apps, Bundle ID = tapera.AMENAPP
```
The old key remains in git history. It cannot be purged from existing commits without a rebase/BFG run, but rotating it makes the historical value useless.

**2. Rotate the Algolia Search Key**
```
Algolia Dashboard → Settings → API Keys → "Search-Only API Key" → Regenerate
Update AMENAPP/AlgoliaConfig.swift with new value (or better: move to xcconfig + Remote Config)
```
Moving the key out of Swift source prevents future git exposure:
```swift
// AlgoliaConfig.swift — preferred
static var searchAPIKey: String {
    Bundle.main.object(forInfoDictionaryKey: "ALGOLIA_SEARCH_KEY") as? String ?? ""
}
```
Add `ALGOLIA_SEARCH_KEY` to `Config.xcconfig` (already gitignored) and `Info.plist`.

---

### High — Fix Before TestFlight / Beta

**3. Move Spotify OAuth Client Secret to Server**
`AMENMediaService.fetchSpotifyToken(clientID:secret:)` does a client-credential OAuth exchange. The `clientSecret` must never be in the app binary.

Recommended approach: Add a `spotifyProxy` Firebase Callable that accepts a search query and returns episodes. The Cloud Function holds `SPOTIFY_CLIENT_SECRET` in Secret Manager and performs the token exchange + search server-side. Remove `SPOTIFY_CLIENT_SECRET` from `Info.plist` and `Config.xcconfig`.

**4. Restrict YouTube API Key in GCP**
In GCP Console → Credentials → the YouTube key: add Application Restrictions = "iOS apps", Bundle ID `tapera.AMENAPP`. This prevents the key being used from any non-app context. Optionally proxy YouTube search through a Cloud Function as well.

**5. Remove CharityNavigatorService Placeholder Key**
Either properly source the key via Remote Config / xcconfig, or remove the entire service if not yet in use. A placeholder string compiled into the binary is an unnecessary code smell.
```swift
// CharityNavigatorService.swift:50 — replace with:
private lazy var apiKey: String = {
    Bundle.main.object(forInfoDictionaryKey: "CHARITY_NAVIGATOR_API_KEY") as? String ?? ""
}()
// Guard at usage:
guard !apiKey.isEmpty else { return }
```

---

### Med — Fix Before Production Launch

**6. Guard PII in dlog() with #if DEBUG**
All email/UID logging already uses `dlog()` which is DEBUG-only. But add an explicit inner `#if DEBUG` guard to log calls that output actual email strings, making the intent clearer and preventing accidental uncommenting of a `print()` path:

```swift
// ClaudeService.swift:246
#if DEBUG
dlog("   User email: \(currentUser?.email ?? "none")")
#endif

// SignInView.swift:1385
#if DEBUG
dlog("📧 Email: \(appleIDCredential.email ?? "none")")
#endif
```

**7. Sanitize systemPromptSuffix Before Injection**

`ClaudeService.buildSystemPrompt` and `OpenAIService.buildSystemPrompt` both append the suffix verbatim. Add a character-limit and strip potential injection payloads:
```swift
private func sanitizedSuffix(_ suffix: String) -> String {
    let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    // Clamp to server-enforced 1500 char limit
    let clamped = String(trimmed.prefix(1500))
    // Strip role-injection attempts
    let stripped = clamped
        .replacingOccurrences(of: "\\n\\s*(system|assistant|user)\\s*:", with: " ", options: .regularExpression)
    return stripped
}
```
Apply before: `prompt += "\n\nAdditional style instruction: \(sanitizedSuffix(suffix))"`

**8. Protect SafetyPlan and TrustedContacts from UserDefaults**

Option A — Keychain (recommended for small data):
```swift
// Replace UserDefaults writes with Keychain read/write
// Using a wrapper like KeychainWrapper or SecItemCopyMatching/SecItemAdd
```

Option B — Encrypted file (`NSFileProtectionCompleteUnlessOpen`):
```swift
let url = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("safetyplan.json")
try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
```
Also set `NSFileProtectionCompleteUnlessOpen` on the file after first write so the data is encrypted on-disk when the device is locked.

**9. Protect Berean Conversation Cache**

`BereanChatView` and `BereanDataManager` store AI conversation history in `UserDefaults`. Move these to a protected file or SQLite database with `NSFileProtectionComplete`:
```swift
// Replace UserDefaults.standard.set(data, forKey: messageCacheKey(for: sessionId))
// with a file-backed cache under .applicationSupportDirectory with .completeFileProtection
```

**10. Verify HealthKit Data Not Persisted Server-Side**

`SynapticStudioView` sends raw `heart_rate` and `hrv` values to the `synapticCreate` Cloud Function. Audit the function implementation to confirm:
- Biometric values are used only to build the AI prompt string and are discarded after.
- The values are not written to Firestore or any analytics pipeline.
- Crashlytics breadcrumbs do not include the numeric values.
Add a comment and a CI check confirming no `heart_rate`/`hrv` fields appear in any `db.collection().set()` call in the function.

**11. Fix Deep Link Host Suffix Check**

```swift
// NotificationDeepLinkRouter.swift:391 — replace:
guard let host = url.host, host.hasSuffix("amenapp.com") else { ... }
// with:
guard let host = url.host,
      host == "amenapp.com" || host.hasSuffix(".amenapp.com") else { ... }
```
This closes the `attackeramenapp.com` theoretical bypass (low real-world risk since AASA pin prevents iOS from routing non-registered hosts, but defense-in-depth is appropriate).

**12. Remove GoogleService-Info.plist from git tracking**

The file is already in `.gitignore` but is still tracked (`git ls-files` confirms it). Remove from tracking without deleting the local file:
```bash
git rm --cached AMENAPP/GoogleService-Info.plist
# Commit the removal, then rotate the API key as per item 1
```

---

### Low — Polish / Hardening

**13. Add backup exclusion to UserDefaults-backed sensitive keys**

Until items 8 and 9 are done, at minimum exclude the safety plan and chat cache from iCloud/iTunes backups by writing them to the `applicationSupportDirectory` with an `.isExcludedFromBackupKey` resource value rather than `UserDefaults`.

**14. Followers-only post rule** — Implement the `users/{authorId}/followers/{followerId}` subcollection and update the Firestore rule as noted in the inline comment at `firestore.rules:596`.

**15. Per-covenant access rule** — Restructure `covenantAccess` as described in the inline comment at `firestore.rules:605`.

---

## Summary

| Priority | Count | Items |
|----------|-------|-------|
| Blocker | 2 | Firebase API key in git, Algolia search key in git |
| High | 3 | Spotify client secret in binary, YouTube key client-side, Charity Navigator placeholder |
| Med | 12 | PII in dlog, systemPromptSuffix injection, safety data in UserDefaults, Berean history in UserDefaults, biometric to AI, deep link suffix check, Firebase key restrictions |
| Low | 3 | Followers-only rules gap, covenant gate gap, deep link hasSuffix |

**AI services (Claude, OpenAI) are correctly proxied** — no on-device keys found for Anthropic or OpenAI. The architecture of routing all AI calls through Firebase Cloud Functions with Secret Manager is sound. The main risks are the Algolia search key and Spotify client secret that still exist in the binary/git, the safety plan PII stored without encryption, and the unsanitized `systemPromptSuffix` injection path.
