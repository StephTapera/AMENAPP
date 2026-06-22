# Connected Intelligence — RUNLOG / Lane Manifest

Branch: `feature/connected-intelligence-20260609` · Firebase: `amen-5e359` · React/TS prototype (SwiftUI deferred).

## Locked decisions
- **Drive + Canva connectors DROPPED** — non-faith-native charter + no `Domain` value + no frozen-enum extension allowed. Ship 4: Calendar, Music, Bible, ChurchMgmt.
- **TrustProfile DROPPED from v1** — absent from the TS contract (`src/berean/contracts.ts`); not needed by any of the 6 surfaces.
- **@mention → Domain folding** (no enum extension): bible→scripture, prayer→prayer, notes→church_notes, calendar→church_notes, sermon→study, music→general, church→admin.
- **CF registration via `functions/v2entry.js`** (v2triggers / Gen-2), matching `bereanChat` — NOT `index.js` (Gen-1 inference taint).
- **Scheduled Actions gated OFF** (`config.scheduledActions.enabled=false`, `aegisReviewId=null`) until Aegis review.
- **P0 (Phase-0 discernmentChecks read-leak): no action** — current rule is already creator-only (firestore.rules ~2230); fixed by concurrent work. Not weakened.

## Commit log (per-item)
- **C1** — Phases 0–3: frozen contract + 6 surfaces (`src/features/**`) + 6 Gen-2 CF modules (`functions/connectedIntelligence/**`) + wiring (v2entry.js ×2, amenRouting.config.js ×2, prepare-deploy.sh, firestore.rules 7 blocks, BereanApp.tsx mounts). tsc 0 errors; grep-lint clean.

## Deploy package (human gates — consolidated for review)
1. Secrets: `GOOGLE_CALENDAR_CLIENT_ID/SECRET`, `SPOTIFY_CLIENT_ID/SECRET` (Pinecone/OpenAI/Anthropic/Gemini already set).
2. Rules deploy = **isMinorSafeDM wiring + the new connected-intelligence block** (the 2156/discernmentChecks fix is already live — exclude from diff). Keep consolidated for human review.
3. Functions deploy via v2triggers codebase (`prepare-deploy.sh`), `--project amen-5e359`.
4. Scheduled Actions stays OFF until Aegis review id assigned.
5. **AIL — `ailTransform` (Accessibility Intelligence Layer)** joins this batch — ONE reviewed deploy, not an ad-hoc push:
   - **Codebase:** gen1 (default `functions/` codebase), NOT v2triggers. Deploy `firebase deploy --only functions:ailTransform --project amen-5e359`.
   - **Export-list diff** (`functions/index.js`, additive): `+ const { ailTransform } = require("./ail/ailTransform"); + exports.ailTransform = ailTransform;`
   - **Routing delta** (`functions/router/amenRouting.config.js`, additive; `CONNECTED_INTELLIGENCE` export preserved): +10 routes — `translate, simplify, explain_scripture, tone_hint, reply_care_check, cooldown_rewrite, describe_image, summarize_audio, reentry_summary, sensitivity_classify`. `explain_scripture` fail_closed/cite-or-refuse; all others fail-open `degrade`.
   - **Secrets:** `ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST` (already set — no new secrets).
   - **Flag appends** (`AMENFeatureFlags.swift`, default **OFF**): `ailToneHintsEnabled, ailImageDescribeEnabled, ailAudioSummaryEnabled, ailVoiceNavEnabled, ailCommentIntentEnabled, ailLargerTouchTargetsEnabled, ailReplyCareEnabled, ailCooldownAssistEnabled, ailEmotionalSafetyFilterEnabled, ailReentrySummaryEnabled`. C1/C2/C13 reuse existing `accessibilityIntelligenceEnabled/meaningAwareTranslationEnabled/readabilityLayerEnabled/naturalModeEnabled`.
   - **Rules (consolidate into the same rules deploy):** `transformCache` server-write-only; `users/{uid}/settings/a11yProfile` owner r/w + forbidden-field schema validation; `captions` subcollection deny-by-default inheriting parent-media read.
   - **Rollback:** purely additive. Revert = remove the `exports.ailTransform` line; flags stay OFF ⇒ zero user-facing surface (all mounts are flag-gated). No data migration; `transformCache` is regenerable.

## Open build items (this session, in progress)
- **2026-06-10 — Berean auth/guest reality:** AMEN does **not** currently support signed-out/Skip browsing for the main app/Berean runtime. DEBUG `Skip` / `Test Mode` buttons are simulator shortcuts only and must not set `isAuthenticated = true` unless Firebase Auth already has a real current user. `ContentView` main startup is intentionally gated on both `authViewModel.isAuthenticated` and `Auth.auth().currentUser?.uid != nil`.
- **connectorFetch read-CF** — consent-gated per connector, computed-and-discarded (no persistence, no payloads in logs), fail-closed fallback preserved.
- **ASWebAuthenticationSession native bridge** — tokens → Keychain, nothing in JS-visible storage; mount `ConnectorsHubScreen` behind flag; retire Berean-v1 connectors screen only after E2E verifies (E2E pending human OAuth secrets).

### 2026-06-10 — FirebaseAI / FirebaseAILogic merge-block diagnosis + resolution

**Symptom (Xcode fresh errors, all from `firebase-ios-sdk/FirebaseAI`):**
- `Type 'LanguageModelSession' does not conform to protocol '_ModelSession'`
- `'Error' is only available in iOS 27.0 or newer`

**Root cause (verbatim, logged for the record):** The FoundationModels (Apple Intelligence) on-device wrapper inside FirebaseAI — `LanguageModelSession+ModelSession.swift`, from firebase PR #16111 "[AI] Add hybrid support with Foundation Models" — **landed in `firebase-ios-sdk` 12.13.0** ("[AI] Add wrapper for FoundationModels.SystemLanguageModel"). The project is pinned to **12.14.0**, so that code is compiled; it requires the iOS 26/27 SDK availability and fails against the app's **iOS 17.0** deployment target. These are compile errors *inside the SDK source* — no app-side Swift change can fix them. The last release before that wrapper is **12.12.0**.

**Decision — NO downgrade.** FirebaseAI/FirebaseAILogic are **UNUSED** (imports commented out; `GoogleGenerativeAI` / `generative-ai-swift` is the app's actual AI dependency, grep-confirmed). Pinning the whole `firebase-ios-sdk` to 12.12.x to keep dead products compiling would freeze Auth / Firestore / Functions / App Check behind a stale SDK for nothing.

**Standing fix — unlink.** Remove **FirebaseAI** + **FirebaseAILogic** from the `AMENAPP` target (human, in Xcode GUI; pbxproj grep verification + immediate commit). `firebase-ios-sdk` **stays at 12.14.0** so every *used* product gets current code. Agent did NOT edit `project.pbxproj` (Xcode open ⇒ corruption risk; no MCP tool for package-product dependencies). pbxproj baseline before unlink: 6 FirebaseAI/FirebaseAILogic reference sites (PBXBuildFile ×2, Frameworks phase ×2, packageProductDependencies ×2, XCSwiftPackageProductDependency defs ×2).

**Re-add path (if on-device FoundationModels via FirebaseAI is ever wanted):** deliberate re-add at a compatible deployment target (iOS 26+), not a passive SDK pin — RUNLOG at that time.

**Next:** on unlink commit landing, run build and continue merge pass from next real compiler errors.
## C2 — Native ASWebAuthenticationSession OAuth bridge (branch `feature/ci-native-bridge-20260609`)
Supplies the missing platform `beginOAuth` so the Connectors Hub can do real OAuth
without stubbing. Additive; reuses the app's Keychain convention; no client secrets.

Files written/edited:
- **Swift (NEW)** `AMENAPP/ConnectedIntelligence/ConnectorOAuthBridge.swift` (~390 lines).
  `WKScriptMessageHandlerWithReply` named `connectorOAuth`. `register(on:presentationAnchorProvider:)`
  attaches it to the prototype WKWebView's `WKUserContentController`. On a JS request it
  generates a PKCE verifier+challenge (S256), stores the verifier in the **Keychain**
  (`com.amenapp.connector.pkce.<state>`, `AfterFirstUnlockThisDeviceOnly`, non-sync),
  builds the provider auth URL (+ `state` CSRF nonce), presents
  `ASWebAuthenticationSession` (ephemeral), validates `state`, extracts `code`, purges
  the verifier, and replies `{ ok, code, redirectUri, codeVerifier }`. Never sees a token.
- **TS (NEW)** `src/features/connectors/oauthConfig.ts` — PUBLIC OAuth params per NEW
  connector (auth endpoint + scopes + redirect `amenapp://oauth/connector`); public
  client_id read from `globalThis.CONNECTOR_OAUTH_CLIENT_IDS` (no hard-coded ids/secrets).
- **TS (NEW)** `src/features/connectors/oauthBridge.ts` — `beginOAuth({id,title})` detects
  `window.webkit.messageHandlers.connectorOAuth`, calls it, returns the short-lived
  `{ code, redirectUri, codeVerifier? }`. **Fails closed** (`NativeBridgeUnavailableError`)
  when no native host → UI shows "open in app to connect", never a fake success.
  `isNativeOAuthBridgeAvailable()` exported for the mount gate.
- **TS (edit)** `src/features/connectors/index.ts` — export bridge API.
- **TS (edit)** `src/features/connectedIntelligence.config.ts` — add
  `connectorsHubUIEnabled` flag (default **false**).
- **TS (edit)** `src/berean/BereanApp.tsx` — the `connectors` tab renders the new
  `ConnectorsHubScreen` (with `beginOAuth`) ONLY when `connectorsHubUIEnabled` **and**
  `isNativeOAuthBridgeAvailable()`; otherwise the **Berean-v1 `ConnectorsScreen` stays the
  default** (not deleted).
- **JS (edit)** `functions/v2triggers/v2entry.js` — add `exports.connectorFetch` to mirror
  `functions/v2entry.js` so the v2triggers deploy bundle is consistent.

Handshake: ConnectorCard → hub `beginOAuth` → `oauthBridge.beginOAuth` →
`connectorOAuth` message handler → `ASWebAuthenticationSession` → redirect `code` →
JS `{code,redirectUri,codeVerifier}` → `provider.grant(...)` → `callOAuthExchange` →
`connectorOAuthExchange` CF (server-side token exchange + `connectorTokens` storage).

Verified: JS import/contract consistency against the existing `ConnectorsHubScreenProps`
/ `GrantParams` / `connectorOAuthExchange` shapes (manual — no tsc binary or node_modules
in this worktree); `functions/v2triggers/v2entry.js` passes `node --check`; Swift reviewed
for correct `WKScriptMessageHandlerWithReply` + `ASWebAuthenticationSession` +
`ASWebAuthenticationPresentationContextProviding` + Keychain usage and default-MainActor
concurrency (stateless helpers marked `nonisolated`). Deploy target iOS 17 supports all APIs.

**E2E — PENDING-SECRETS:** the full round-trip against real Google Calendar / Spotify
requires `GOOGLE_CALENDAR_CLIENT_ID/SECRET` + `SPOTIFY_CLIENT_ID/SECRET` (server) and the
matching PUBLIC client ids injected as `CONNECTOR_OAUTH_CLIENT_IDS` (client). These are not
provisioned, so the live OAuth E2E is **NOT run** and is **not faked**. Flip
`connectorsHubUIEnabled` → true only after E2E passes with provisioned secrets.

**Human steps:** (1) Add `AMENAPP/ConnectedIntelligence/ConnectorOAuthBridge.swift` to the
AMENAPP app target (Xcode target membership) and run an Xcode build — cannot build from this
worktree. (2) When the prototype WKWebView host is built, call
`ConnectorOAuthBridge.register(on: webView.configuration.userContentController) { anchorWindow }`.
(3) Provision the 4 OAuth secrets + inject the public client ids; then E2E + flip the flag.

---

## QUARANTINE — duplicate Connected Intelligence implementation (RULING 2026-06-09)

**Ruling:** the contract-corrected stack WINS. The parallel implementation was built on
the REJECTED contract (autonomous-write `ScheduleWriteRisk.External` tier + collapsed
enums = doctrine violation at the foundation). One Connected Intelligence implementation
exists from now on.

**Inventory (which world):**
- **Duplicate** committed on `rescue/verification-and-safety-0609` at **`12f8839f`**
  ("rescue: durable snapshot…") — full `src/features/**` + 5 CF modules on the BROKEN
  contract (rescue HEAD still carries `grantedVia`/`Settings`, 2 broken-markers).
- **Stranded lane** `feature/connected-intelligence-20260609` (cc9cd5d3): NO CI files.
- **Integration path** `integration/recover-features-20260609`: NO CI files (0 broken-markers,
  contract absent). **The duplicate has NOT propagated to the integration target.**
- **CANONICAL corrected stack** = branch **`ci/contract-faithful`** (== `feature/ci-native-bridge-20260609`):
  `7695189b` (Phases 0–3 corrected contract + wiring) → `37129fb3` (connectorFetch) →
  `f3e0866d` (native OAuth bridge). Verified: contract 0 broken-markers; ZERO broken-symbol
  usage across `src/features`.

**Supersession (ruling 1b):** because the integration path carries no CI, there is nothing
of the duplicate to revert there — the reconciler takes `ci/contract-faithful` WHOLESALE as
the sole CI source and DISCARDS `12f8839f`'s CI files. `rescue` itself is left untouched
(shared, in active use by Xcode + other lanes); its `12f8839f` CI files are quarantined =
do-not-integrate.

**Discard default (ruling 1c):** nothing from `12f8839f` ports over unless re-verified
line-by-line against the corrected contract. Default = discard. The parallel
"Design swarm orchestration for Amen Connected Intelligence" conversation is FORMALLY
CLOSED OUT — superseded by `ci/contract-faithful`.

**Cleanup:** removed `src/features/.subagent_probe` (junk write-probe snapshotted into
`12f8839f`, inherited onto the branch).

## RULING 3 — WKWebView host registration: BLOCKED (host does not exist)
Grep of `AMENAPP/**` for `dist/berean` / `loadFileURL` / `messageHandlers` / `connectorOAuth`
/ `BereanApp` → **no matches**. The React prototype is NOT embedded in a native WKWebView
anywhere in the app; the 4 WKWebViews present host other content (in-app browser, media,
resources, sermons), none load the prototype. So there is no host file (and no inactive lane)
to claim — registration is blocked on the deferred React→native embedding (§1.10 SwiftUI
parity), NOT on lane contention. `ConnectorOAuthBridge.register(on:)` is ready; the human
calls it once a prototype-hosting WKWebView exists. Nothing fabricated.

## RULING 4 — Stage 3 functions deploy batch (confirmed)
- Rules diff = **isMinorSafeDM wiring + CI block ONLY** (firestore.rules:2156/discernmentChecks
  already live — exclude).
- Stage 3 functions batch = `connectorFetch` + `connectorOAuthExchange` + `ailTransform`
  + the 6 CI CF modules, deployed via the v2triggers codebase, `--project amen-5e359`.

## RULING 5 — FirebaseAI linkage cleanup (confirmed)
- FirebaseAI/FirebaseAILogic permanently unlinked — app uses GoogleGenerativeAI; do not re-add.

## RULING 6 — package-saga root cause = iCloud sync (2026-06-10, confirmed)
- **Root cause:** the project lived under iCloud Desktop sync; the file-provider daemon evicted
  SwiftPM package files mid-build (`com.apple.fileprovider.fpfs#P` xattr → `resolved source packages:`
  empty / `"csharp_generator_unittest.cc" doesn't exist` / `dependency … missing` / codesign
  `resource fork … not allowed`). NOT FirebaseAI, NOT stale cache, NOT junk dups.
- **Durable fix:** `.nosync`-suffixed build dirs are iCloud-excluded. Standard build flags are now
  `-clonedSourcePackagesDirPath ./SourcePackages.nosync -derivedDataPath ./DerivedData.nosync
  -packageCachePath ./PackageCache.nosync` (+ `-project AMENAPP.xcodeproj`; `CODE_SIGNING_ALLOWED=NO`
  for sim). **Post-ship the repo moves to `~/Developer`.**
- **No lane re-diagnoses package corruption without first checking this ruling.**
