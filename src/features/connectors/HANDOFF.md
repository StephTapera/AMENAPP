# Connectors Hub — HANDOFF (Phase 2 Agent A)

Branch: `feature/connected-intelligence-20260609`
Owner module (backend): `functions/connectedIntelligence/connectorFunctions.js`
Owner UI: `src/features/connectors/**`

Agent A did NOT edit any shared file. The deltas below must be applied by a human
(or the shared-file owner) to wire this up.

---

## 1. Cloud Function exports to register

In **`functions/index.js`** add (mirrors the existing `require`/`exports` pattern):

```js
const connectorFns = require('./connectedIntelligence/connectorFunctions');
exports.connectorOAuthExchange = connectorFns.connectorOAuthExchange;
exports.connectorUpdateGrant   = connectorFns.connectorUpdateGrant;
exports.connectorRevoke        = connectorFns.connectorRevoke;
exports.connectorStatus        = connectorFns.connectorStatus;
```

These are v2 `onCall` callables (region `us-central1`). No trigger wiring needed.

### Secrets to provision (Functions params / Secret Manager)
The OAuth callable binds these via `defineSecret` — set them before deploy:

```
firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_ID
firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_SECRET
firebase functions:secrets:set SPOTIFY_CLIENT_ID
firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
```

Tokens are stored server-side only and never returned to the client.

---

## 2. Firestore rules needed

Add to **`firestore.rules`**:

```
// Connector grant docs — user owns their own; minors blocked at the CF, but
// also deny client WRITE so only the Cloud Function (admin SDK) can mint grants.
match /users/{uid}/connectorGrants/{connectorId} {
  allow read:  if request.auth != null && request.auth.uid == uid;
  allow write: if false;          // grants written by Cloud Functions only
}

// Connector OAuth tokens — PRIVATE. Deny ALL client access. Admin SDK only.
match /connectorTokens/{docId} {
  allow read, write: if false;
}
```

> The CF writes grants with `minorBlocked: true` and rejects minors (ageTier != 'tierD')
> before any grant doc is created — the `allow write: if false` rule is defense-in-depth.

---

## 3. amenRouting.config.js flags

Add to **`functions/router/amenRouting.config.js`** (server mirror of
`connectedIntelligence.config.ts`). These gate the connectors at the router level:

```js
connectedIntelligence: {
  connectors: { calendar: { enabled: true }, music: { enabled: true } },
  limits: {
    connectorRequestsPerDay: 100,   // matches config + connectorStatus CF rate limit
    dailyPromptsFree: 25,
    dailyPromptsPlus: 200,
  },
},
```

Kill-switch suggestion: a single `connectedIntelligence.connectorsEnabled` boolean the
CFs can check first to hard-disable all connectors without a redeploy.

---

## 4. App mount point

Mount the hub from the host app's settings/integrations route:

```tsx
import { ConnectorsHubScreen } from '@/features/connectors';

<ConnectorsHubScreen
  minorScoped={account.ageTier !== 'tierD'}   // anything but confirmed-adult ⇒ explainer
  plan={account.plan}                          // 'free' | 'plus' | 'pro'
  beginOAuth={hostOAuthBridge}                 // opens system web-auth, returns { code, redirectUri, codeVerifier? }
/>
```

`beginOAuth` is the platform OAuth bridge supplied by the host (iOS opens an
`ASWebAuthenticationSession`). It returns ONLY an authorization code — never a token.
The code is exchanged for tokens **server-side** in `connectorOAuthExchange`.

Other Connected Intelligence surfaces should import the reusable degraded/cap chips:

```tsx
import { DegradedChip, CapChip } from '@/features/connectors';
```

---

## 5. Note for SwiftUI parity (later)
Calendar provider ships Google Calendar v1; Apple EventKit lands at SwiftUI parity.
Music ships Spotify v1; Apple Music later — both already behind the `MusicProvider`
adapter so no UI change is needed when the provider is swapped.
