# Security and Secrets Report
Generated: 2026-06-16 | Branch: app-store-readiness-overnight

All secret values are REDACTED in this document. File paths and line numbers are provided.
No raw credential values appear in this report.

---

## Findings

### S-001 — Firebase API Key in GoogleService-Info.plist (SEC-001)

**Severity:** P2 YELLOW
**File:** `AMENAPP/AMENAPP/GoogleService-Info.plist`, line 10
**Pattern:** `AIzaSy…` (redacted)
**Risk:** The Firebase API key is committed to git history. Firebase restricts this key by bundle ID and SHA-1 fingerprint, so it is intentionally bundled per Firebase design. However, if the repository has ever been public or has had non-trusted contributors, the key may have been extracted.

**Status:** Not auto-rotated by agent. Requires human verification.

**Required action:**
1. In the Firebase console, navigate to Project Settings > API credentials
2. Confirm the key has application restrictions: iOS apps with the exact bundle ID and all valid SHA-1 fingerprints (debug, release, CI)
3. If repo history has been public: regenerate the key in Firebase console, download a new `GoogleService-Info.plist`, inject via CI secret manager going forward
4. Add `GoogleService-Info.plist` to `.gitignore` if not already present

---

### S-002 — xcconfig Variable-Substituted Keys in Info.plist (GREEN — SEC-009)

**Severity:** P3 GREEN
**File:** `AMENAPP/AMENAPP/Info.plist`
**Pattern:** `$(VAR_NAME)` substitutions
**Keys using xcconfig injection:**
- `ALGOLIA_SEARCH_KEY` (line 6)
- `GOOGLE_VISION_API_KEY` (line 53)
- `VERTEX_AI_KEY` (line 83)
- `YOUTUBE_API_KEY` (line 85)
- `YOUVERSION_API_KEY` (line 87)
- `SPOTIFY_CLIENT_ID` (line 69)
- `FEED_RANKING_URL` (line 49)
- `SEARCH_SERVICE_URL` (line 67)

**Status:** Correct pattern. No literal key values are hardcoded.

**Verification required (human):** Confirm the xcconfig files supplying these values are NOT committed to the repo. Run `git ls-files | grep xcconfig` and confirm they are in .gitignore. Confirm CI/CD injects all values so the build does not embed empty strings.

---

### S-003 — Backend TypeScript Source (GREEN — SEC-011)

**Severity:** P3 GREEN
**Path:** `Backend/functions/src/`
**Grep patterns checked:** `AIza[0-9A-Za-z_-]{10}`, `sk-[a-zA-Z0-9]{10,}`, `algoliaKey =`
**Result:** No matches found. Backend secrets are not hardcoded in TypeScript source.

**Verification required (human):** Confirm secrets are injected via Firebase Secret Manager or Cloud Run environment variables at deploy time. Run `firebase functions:secrets:list --project amen-5e359` to list configured secrets.

---

### S-004 — bypassAuthForTesting() (GREEN — SEC-002)

**Severity:** P3 GREEN
**File:** `AMENAPP/AMENAPP/AuthenticationViewModel.swift`, line 2417
**Pattern:** Defined inside `#if DEBUG` block; called only from `#if DEBUG` blocks in AMENAuthLandingView.swift and MinimalAuthenticationView.swift
**Status:** Correctly stripped from release builds. No action required.

---

### S-005 — Emulator Configuration (GREEN — SEC-003, already fixed)

**File:** `AMENAPP/AMENAPP/CloudFunctionsService.swift`
**Status:** Dead commented-out `useEmulator` line was removed by SEC-003 auto-fix. No active localhost or 127.0.0.1 references in Swift code.

---

### S-006 — Production APNs Environment (GREEN — SEC-004)

**Files:** `AMENAPP/AMENAPP/AMENAPP.entitlements` (line 10), `AMENAPP/AMENAPP/AMENAPP.release.entitlements` (line 10)
**Value:** `production` in both files
**Status:** Correct for App Store distribution. No action required.

---

### S-007 — ATS Enforcement (GREEN — SEC-005)

**File:** `AMENAPP/AMENAPP/Info.plist`
**Status:** No `NSAppTransportSecurity` dictionary and no `NSAllowsArbitraryLoads` key in production plist. ATS is fully enforced.

---

### S-008 — Entitlements Requiring Apple Pre-Approval (SEC-007, SEC-008)

**Severity:** P2 YELLOW

**File:** `AMENAPP/AMENAPP/AMENAPP.entitlements`

`com.apple.developer.background-tasks.continued-processing.gpu` (line 15, value: true)
- Requires explicit Apple approval and provisioning in the Developer portal
- If not approved, app installation and archive validation will fail
- If not actively used: remove from both entitlements files before submission

`com.apple.developer.location.push` (line 27, value: true)
- Requires a special entitlement request from Apple
- Used for region-monitoring push notifications
- If not approved and in the provisioning profile, app installation will fail

**Action:** In the Apple Developer portal, confirm both entitlements are:
1. Listed in your App ID's capabilities
2. Present in the App Store distribution provisioning profile

If either is not approved, remove it from both `AMENAPP.entitlements` and `AMENAPP.release.entitlements` before submitting.

---

### S-009 — Debug and Release Entitlements Diverge (SEC-010)

**Severity:** P2 YELLOW
**Files:** `AMENAPP/AMENAPP/AMENAPP.entitlements` (debug), `AMENAPP/AMENAPP/AMENAPP.release.entitlements` (release)

**Present in debug but absent from release:**
- `com.apple.developer.siri` (line 35 of debug file)
- `com.apple.developer.usernotifications.time-sensitive` (line 30 of debug file)

**Risk:** If the Release build configuration uses the debug entitlements file (check Xcode target Signing & Capabilities), Siri integration will be active in production. If the release file is used, Siri intents and time-sensitive notifications will be silently unavailable in production.

**Action:**
1. In Xcode, check target > Signing & Capabilities > Code Signing Entitlements for the Release configuration
2. If Siri and time-sensitive notifications are intended for production: add both keys to `AMENAPP.release.entitlements`
3. If not production-ready: remove from debug entitlements to prevent accidental inclusion

---

### S-010 — No Admin UID Hardcoding in Backend (GREEN — FIRE-014)

**Severity:** P0 GREEN
**Path:** `Backend/functions/src/`, `functions/src/`
**Status:** No hardcoded admin UID lists found. Admin privilege gated exclusively on custom token claims (`context.auth.token.admin`, `request.auth.token.get('role', '')`).

---

## Rotation Preparation

For each secret that requires rotation or verification before App Store submission:

| Secret | What It Is | Where It Should Live | Firebase Secret Manager Path | Rotation Steps |
|---|---|---|---|---|
| Firebase API Key | App-level Firebase authentication key (AIzaSy…) | GoogleService-Info.plist injected via CI — NOT committed | N/A (bundle-restricted; Firebase manages) | Firebase console > Project Settings > Regenerate |
| ALGOLIA_SEARCH_KEY | Algolia public search-only key for client-side search queries | xcconfig injected at build time | `ALGOLIA_SEARCH_KEY` xcconfig var | Algolia dashboard > API Keys > Regenerate |
| GOOGLE_VISION_API_KEY | Google Vision API key for OCR / Berean Lens | xcconfig injected at build time | Consider moving to CF proxy; key should not be in client binary if possible | GCP console > APIs & Services > Credentials |
| VERTEX_AI_KEY | Vertex AI (Gemini) key | xcconfig injected at build time | Move to CF callable instead of client-side; CF should proxy all AI calls | GCP console > APIs & Services > Credentials |
| YOUTUBE_API_KEY | YouTube Data API v3 key | xcconfig injected at build time | GCP console > YouTube API key | GCP console > APIs & Services > Credentials |
| YOUVERSION_API_KEY | YouVersion Bible content API key | xcconfig injected at build time | YouVersion developer dashboard | YouVersion developer dashboard |
| SPOTIFY_CLIENT_ID | Spotify app OAuth client ID | xcconfig injected at build time; not a secret (public OAuth client ID) | N/A (public client ID; rotate only if compromised) | Spotify developer dashboard |
| Firebase functions secrets | CLAUDE_API_KEY, OPENAI_API_KEY, NCMEC credentials, Stripe keys | Firebase Secret Manager | `firebase functions:secrets:list` | Firebase console > Functions > Secrets |

---

## Preflight Secret Detection Script

Run before every commit and in CI pre-merge to detect accidentally committed secrets:

```bash
#!/bin/bash
# preflight-secrets.sh
# Run from repo root before every commit
# Usage: bash preflight-secrets.sh

set -e

echo "Scanning for secrets in staged files..."

# Check staged diff for common secret patterns
STAGED=$(git diff --cached)

if echo "$STAGED" | grep -qE "AIza[0-9A-Za-z_-]{35}"; then
    echo "FAIL: Firebase API key pattern detected in staged diff"
    exit 1
fi

if echo "$STAGED" | grep -qE "sk-[a-zA-Z0-9]{48}"; then
    echo "FAIL: OpenAI API key pattern detected in staged diff"
    exit 1
fi

if echo "$STAGED" | grep -qE "sk-ant-[a-zA-Z0-9_-]{40,}"; then
    echo "FAIL: Anthropic API key pattern detected in staged diff"
    exit 1
fi

if echo "$STAGED" | grep -qE "['\"]algolia['\"]:\s*['\"][A-Z0-9]{32}['\"]"; then
    echo "FAIL: Algolia key literal detected in staged diff"
    exit 1
fi

if echo "$STAGED" | grep -qE "GOOGLE_VISION_API_KEY\s*=\s*AIza"; then
    echo "FAIL: Google Vision API key literal detected in staged diff"
    exit 1
fi

# Check for GoogleService-Info.plist being staged
if git diff --cached --name-only | grep -q "GoogleService-Info.plist"; then
    echo "WARNING: GoogleService-Info.plist is being staged. Verify this is intentional."
    echo "If this file contains a real API key, remove it and inject via CI secrets."
    # Not a hard fail — the key is bundle-restricted — but warn loudly
fi

# Check for xcconfig files being staged
if git diff --cached --name-only | grep -q "\.xcconfig"; then
    echo "WARNING: .xcconfig file is being staged. Verify it contains only $(VAR) references, not literal key values."
fi

echo "No critical secret patterns found in staged diff."
exit 0
```

Add to `.git/hooks/pre-commit` or CI pipeline step before `git commit`.

---

## Hardcoded Admin / Debug Bypass Findings

| Location | Pattern Found | Status |
|---|---|---|
| AuthenticationViewModel.swift line 2417 | `bypassAuthForTesting()` | SAFE — inside `#if DEBUG` |
| AMENAuthLandingView.swift line 163 | Call to `bypassAuthForTesting()` | SAFE — inside `#if DEBUG` |
| MinimalAuthenticationView.swift line 426 | Call to `bypassAuthForTesting()` | SAFE — inside `#if DEBUG` |
| AuthDebugView.swift (all 811 lines) | Create user, sign-in, Firestore delete | SAFE — entire file wrapped in `#if DEBUG` / `#endif` |
| CloudFunctionsService.swift | `// functions.useEmulator(...)` | FIXED — line removed by SEC-003 auto-fix |
| Backend/functions/src/ | Hardcoded admin UID arrays | NONE FOUND — admin gated on custom token claims |
| functions/src/ | Hardcoded admin UID arrays | NONE FOUND |
| GroupAdminView.swift line 481 | `groupMembers[index].isAdmin = true` | SAFE — local UI state update after verified Firestore write |
