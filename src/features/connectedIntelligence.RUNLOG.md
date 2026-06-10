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
