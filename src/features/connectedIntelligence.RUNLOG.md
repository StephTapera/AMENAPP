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

## Open build items (this session, in progress)
- **connectorFetch read-CF** — consent-gated per connector, computed-and-discarded (no persistence, no payloads in logs), fail-closed fallback preserved.
- **ASWebAuthenticationSession native bridge** — tokens → Keychain, nothing in JS-visible storage; mount `ConnectorsHubScreen` behind flag; retire Berean-v1 connectors screen only after E2E verifies (E2E pending human OAuth secrets).
