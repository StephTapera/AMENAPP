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
