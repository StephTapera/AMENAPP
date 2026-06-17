# Security and Secrets Audit — 2026-06-16

Generated: 2026-06-16 | Branch: feature/berean-island-w0
Audit scope: all first-party Swift, TypeScript, shell, plist, and xcconfig files in repo root.
Excluded from scan: SourcePackages.nosync, DerivedData.nosync, .spm, Backend/rules-tests/node_modules, .claude/worktrees (agent-workspace copies), AMEN_FINAL_10_GO_RESULTS.

**All secret values are REDACTED in this document. File paths and line numbers are provided for human review.**

---

## Secrets Found This Run

### S-001 — Firebase API Key in GoogleService-Info.plist (P1 RED — BLOCKING)

| Field | Value |
|---|---|
| Type | Firebase / Google iOS API key (AIzaSy…) |
| File | `AMENAPP/GoogleService-Info.plist`, line 10 |
| Git-tracked | YES — confirmed by `git ls-files AMENAPP/GoogleService-Info.plist` |
| Committed since | Initial commit (`01adf60c`) |
| Also present | `.claude/worktrees/agent-*/AMENAPP/GoogleService-Info.plist` (16+ agent worktree copies — derived from the tracked file; all contain the same key value) |

**Risk:** The Firebase API key has been in git history since the first commit. Although Firebase restricts this key to requests matching the registered bundle ID and SHA-1 fingerprints, any person who has ever cloned this repo has the key value. If the bundle restrictions were ever misconfigured (or if this repo has been public at any point), the key could be used to access Firebase resources (Firestore reads gated only by security rules, Authentication for sign-in flows, etc.).

**Required rotation steps:**
1. In the Firebase console: Project Settings > Your apps > iOS app > API key > Regenerate
2. Download the new `GoogleService-Info.plist` from the Firebase console
3. Add `GoogleService-Info.plist` to `.gitignore` (it is NOT currently excluded — only `*.xcconfig` is excluded)
4. Remove the tracked file from git: `git rm --cached AMENAPP/GoogleService-Info.plist`
5. Inject the new file via CI (GitHub Actions secret or Xcode Cloud environment file)
6. Consider running `git filter-repo --path AMENAPP/GoogleService-Info.plist --invert-paths` to purge the key from all history, then force-push (requires team coordination)

**New path after remediation:** CI secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` → decoded at build time to `AMENAPP/GoogleService-Info.plist`

---

### S-002 — xcconfig Variable-Substituted Keys in Info.plist (P3 GREEN — Correct pattern)

| Key | Info.plist line | Substitution variable |
|---|---|---|
| ALGOLIA_SEARCH_KEY | 6 | `$(ALGOLIA_SEARCH_KEY)` |
| GOOGLE_VISION_API_KEY | 53 | `$(GOOGLE_VISION_API_KEY)` |
| VERTEX_AI_KEY | 83 | `$(VERTEX_AI_KEY)` |
| YOUTUBE_API_KEY | 85 | `$(YOUTUBE_API_KEY)` |
| YOUVERSION_API_KEY | 87 | `$(YOUVERSION_API_KEY)` |
| SPOTIFY_CLIENT_ID | 69 | `$(SPOTIFY_CLIENT_ID)` |
| FEED_RANKING_URL | 49 | `$(FEED_RANKING_URL)` |
| SEARCH_SERVICE_URL | 67 | `$(SEARCH_SERVICE_URL)` |

**Status:** Correct pattern — no literal key values are hardcoded in Info.plist. `Config.xcconfig` is in `.gitignore` and only a `Config.xcconfig.template` is tracked.

**Verification required (human):**
- Run `git ls-files | grep xcconfig` to confirm no real xcconfig with values is tracked
- Confirm CI/CD injects all xcconfig variable values so the build does not embed empty strings in the binary

---

### S-003 — Backend TypeScript Cloud Functions (P3 GREEN — Correct pattern)

| Pattern scanned | Result |
|---|---|
| Literal `AIza[…]{35}` in .ts files | None found in first-party source |
| `OPENAI_API_KEY = "…"` (literal) | None — uses `defineSecret('OPENAI_API_KEY')` in context CFs |
| `CLAUDE_API_KEY = "…"` (literal) | None — uses `defineSecret('CLAUDE_API_KEY')` |
| `sk-ant-` prefix in .ts | Only in `functions/src/sanctuary/sanctuary.test.ts:312` — test mock value `"test-key"`, not a real key |
| Stripe keys | None in first-party source |

**Status:** All backend secrets correctly routed through Firebase Secret Manager (`defineSecret`). No hardcoded production credentials found.

---

### S-004 — bypassAuthForTesting() Debug Backdoor (P3 GREEN — Correctly gated)

| File | Line | Guard |
|---|---|---|
| `AMENAPP/AuthenticationViewModel.swift` | 2417 | `#if DEBUG` / `#endif` |
| `AMENAPP/AMENAuthLandingView.swift` | 163 | `#if DEBUG` / `#endif` |
| `AMENAPP/MinimalAuthenticationView.swift` | 426 | `#if DEBUG` / `#endif` |
| `AMENAPP/AuthDebugView.swift` | All 811 lines | Entire file in `#if DEBUG` |

**Status:** Stripped from Release builds by compiler. No action required.

---

### S-005 — Emulator Configuration (P3 GREEN — Already fixed)

**File:** `AMENAPP/CloudFunctionsService.swift`
**Status:** Dead `useEmulator(...)` line was removed by prior SEC-003 auto-fix. No active `localhost` or `127.0.0.1` references in any Swift source.

---

### S-006 — No Hardcoded Admin UIDs in Backend (P0 GREEN)

**Scanned:** `Backend/functions/src/`, `functions/src/`
**Result:** No hardcoded admin UID arrays found. Admin privilege is gated exclusively on custom token claims (`context.auth.token.admin`, `request.auth.token.get('role', '')`).

---

## Required Rotations (P0 / P1 — Blocking)

| # | Secret type | Found in | Priority | Rotation steps | New path |
|---|---|---|---|---|---|
| R-001 | Firebase iOS API key (AIzaSy…) | `AMENAPP/GoogleService-Info.plist` line 10, git history since `01adf60c` | **P1 BLOCKING** | Firebase console > Regenerate; remove file from git tracking; inject via CI | CI secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` → decoded at build time |

No other production secrets requiring immediate rotation were found in first-party source.

---

## Verification Required (Human Steps)

| # | Action | Owner |
|---|---|---|
| V-001 | Confirm `Config.xcconfig` (with real key values) is NOT in git: `git ls-files \| grep xcconfig` | Human |
| V-002 | Confirm all xcconfig keys resolve at CI build time (not empty strings): check CI build log | Human |
| V-003 | Rotate Firebase API key per R-001 above; update CI secret | Human |
| V-004 | Add `AMENAPP/GoogleService-Info.plist` to `.gitignore` and run `git rm --cached` | Human |
| V-005 | Confirm Firebase app restrictions for the current key include only production bundle ID + SHA-1 fingerprints | Human |
| V-006 | Run `firebase functions:secrets:list --project amen-5e359` to verify all backend secrets are configured | Human |

---

## Preflight Secret Detection Script

Script written to: `scripts/check-secrets-preflight.sh`
Executable: yes

The script scans `git diff --cached` for 14 patterns (S-001 through S-014):
- Firebase/Google API keys (AIzaSy…) — FAIL
- OpenAI keys (sk-…) — FAIL
- Anthropic keys (sk-ant-…) — FAIL
- Stripe live keys (sk_live_…) — FAIL
- Stripe test keys (sk_test_…) — WARNING
- Algolia API key literals — FAIL
- Google Vision / Vertex AI key literals — FAIL
- FCM server keys (AAAA…) — FAIL
- PEM private key blocks — FAIL
- High-entropy credential assignments (heuristic) — WARNING
- GoogleService-Info.plist staged — WARNING
- xcconfig file staged — WARNING
- .env file staged — FAIL
- Firebase service account JSON staged — FAIL

**To install as a git pre-commit hook:**
```bash
cp scripts/check-secrets-preflight.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**To run manually before a commit:**
```bash
bash scripts/check-secrets-preflight.sh
```

---

## Client-Side Security Issues

| Location | Pattern | Status |
|---|---|---|
| `AuthenticationViewModel.swift` line 2417 | `bypassAuthForTesting()` | SAFE — `#if DEBUG` only |
| `AMENAuthLandingView.swift` line 163 | Call to `bypassAuthForTesting()` | SAFE — `#if DEBUG` only |
| `MinimalAuthenticationView.swift` line 426 | Call to `bypassAuthForTesting()` | SAFE — `#if DEBUG` only |
| `AuthDebugView.swift` (811 lines) | Create user, sign-in, Firestore delete | SAFE — entire file `#if DEBUG` |
| `CloudFunctionsService.swift` | `useEmulator(...)` | FIXED — removed by SEC-003 |
| `Backend/functions/src/` | Hardcoded admin UID arrays | NONE — claims-based only |
| `functions/src/` | Hardcoded admin UID arrays | NONE — claims-based only |
| `GroupAdminView.swift` line 481 | `groupMembers[index].isAdmin = true` | SAFE — local UI state after verified Firestore write |

---

## Phase 13–14 Addendum (from prior audit agents, preserved here)

### P13-G1 — AskSelahView uncancelled Task{} calls (FIXED GREEN)
File: `AMENAPP/AskSelahView.swift`. Two fire-and-forget `Task {}` calls had no cancellation path. Fix applied: `@State private var activeTask: Task<Void, Never>?` stored and cancelled on `onDisappear`.

### P13-G2 — assertionFailure usage (CLEAN)
`AMENAPP/AIIntelligence/AmenAIFeaturesService.swift:108`, `AMENAPP/FirebasePostService.swift:2143`, `AMENAPP/AMENAPP/GlobalResilience/GlobalResilienceWiring.swift:35`, `AMENAPP/AMENAuthLandingView.swift:516` — all no-op in Release builds. Clean.

### P13-G3 — Pagination, MainActor, listener cleanup (ALL CLEAN)
Firestore queries use `.limit(to:)` throughout. `@MainActor` consistently applied. All major services store and remove `ListenerRegistration` tokens.

### P14-G1 — Algolia Application ID (182SCN7O9S) in AlgoliaConfig.swift (ACCEPTABLE)
Public read identifier per Algolia security model — not a secret.

### P14-G2 — Algolia Search API Key (CLEAN)
Read from `Bundle/Info.plist` via xcconfig injection. Previous key rotated 2026-06-03.

### P14-G3 — YouTube/Unsplash apiKey variables in AMENDiscoveryView.swift (VERIFY)
Lines 2461 and 2598 interpolate `apiKey` into URLs. Source must be confirmed as Remote Config or xcconfig, not a hardcoded literal. No `AIza` prefix literal was found in the first-party Swift source scan above — this item is tentatively CLEAN but requires human verification of the runtime value source.

### P14-G4 — No emulator endpoints, no client admin backdoors, no fatalError (ALL CLEAN)
Confirmed by this run.

---

## APNs and Entitlement Issues

### S-008 — Entitlements Requiring Apple Pre-Approval (P2 YELLOW)

**File:** `AMENAPP/AMENAPP/AMENAPP.entitlements`

- `com.apple.developer.background-tasks.continued-processing.gpu` (line 15): requires Apple approval
- `com.apple.developer.location.push` (line 27): requires special entitlement request from Apple

If not approved in the provisioning profile, app installation and archive validation will fail.

### S-009 — Debug and Release Entitlements Diverge (P2 YELLOW)

Present in debug but absent from `AMENAPP.release.entitlements`:
- `com.apple.developer.siri`
- `com.apple.developer.usernotifications.time-sensitive`

Verify which entitlements file the Release build configuration references in Xcode.

---

## Summary Counts

| Category | Count |
|---|---|
| Secrets found (real, first-party source) | 1 (Firebase API key in tracked plist) |
| Rotation required — P1 BLOCKING | 1 (R-001) |
| Green / correctly handled | 5 (S-002 through S-006) |
| Human verifications required | 6 (V-001 through V-006) |
| Preflight script patterns | 14 |
| Client-side security issues (open) | 0 |

---

## Current Pass Addendum — 2026-06-16

Current Git branch observed by this agent: `app-store-readiness-overnight`.

### Config Tracking Check

`git ls-files -- Config.xcconfig AMENAPP/Config.xcconfig AMENAPP/AMENAPP/Config.xcconfig` returned no tracked config files. `.gitignore` currently ignores `Config.xcconfig` and `*.xcconfig`.

### Algolia Key Status

| Item | Current Finding | Lane | Action |
|---|---|---|---|
| `AMENAPP/Config.xcconfig` | Contains `ALGOLIA_SEARCH_KEY` in an ignored local config file. Not tracked in current Git index. | 🟡 | Rotate if this value has ever been committed/shared; keep only restricted search keys in local configs. |
| `firebase-debug*.log` | Local debug logs contain deployed function inventory and environment variables including `ALGOLIA_APP_ID`; logs are not appropriate release artifacts. | 🟢/🟡 | Delete or quarantine local debug logs before packaging handoff; do not commit them. If logs include secret values, rotate affected secrets. |

### Verification Commands

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
git ls-files -- Config.xcconfig AMENAPP/Config.xcconfig AMENAPP/AMENAPP/Config.xcconfig
bash scripts/check-secrets-preflight.sh
```
