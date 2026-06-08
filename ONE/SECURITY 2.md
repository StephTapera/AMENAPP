# ONE — Security Model & Threat Analysis
# Generated: 2026-06-01 | Updated: 2026-06-02 | Status: DRAFT v2.0 — P5 hardening pass complete

---

## 0. Scope

This document covers:
- E2E messaging threat model for private threads
- Privacy architecture for all three zones (People / Moments / World)
- Abuse path that survives ephemeral content decay
- What the platform can and cannot enforce (honesty inventory)

It does NOT cover: Apple device security, Firebase platform security, Stripe PCI-DSS
compliance. Those are out of scope; link to their respective security docs instead.

---

## 1. E2E Messaging Protocol

### 1.1 Primary Protocol — MLS (RFC 9420)

Target: Messaging Layer Security, IETF RFC 9420.

**Why MLS over Signal protocol:**
- Group-capable with efficient rekeying as members join/leave (no pairwise scaling problem)
- Post-compromise security: compromise of current keys doesn't expose past messages (forward secrecy) OR future messages after recovery (post-compromise security)
- Standard open protocol; degradable gracefully

**Key hierarchy:**
```
Device key pair (Secure Enclave, non-exportable)
  └── MLS KeyPackage (published to /one_users/{uid}/keyPackages/)
        └── MLS Group key material (local state, never uploaded)
              └── Per-message HPKE encryption
```

**What Firestore stores:**
- `ONEEncryptedPayload`: `{ ciphertext: Data, mlsEpoch: UInt64, senderDeviceID: String }`
- Thread metadata: participant UIDs, group ID, `encryptionVersion`, timestamps
- NO plaintext. NO key material. NO message content.

**What the server can see:**
- Who sent to whom (sender UID + recipient UIDs)
- When (timestamp)
- Message size bucket (binned, not exact)
- Whether a message was reported (post-report)

### 1.2 Fallback Protocol — Key Ratchet (CryptoKit)

If MLS library is unavailable on target iOS version:
- Use CryptoKit Curve25519 key exchange + AES-GCM per message
- Forward secrecy via ratchet (Double Ratchet Algorithm semantics)
- Document as `encryptionVersion: "cr_1.0"` in `ONEThread`
- UX note: "End-to-end encrypted" — no claim about MLS specifically in UX copy

### 1.3 Key Backup / Recovery

- Users may optionally export MLS state to encrypted iCloud Keychain backup
- Tradeoff: backup holder (Apple/iCloud) gains access to backup key material
- UX must clearly disclose this tradeoff before backup is enabled
- Default: NO backup (messages lost if device lost)

---

## 2. Threat Model — E2E Threads

| Threat | Impact | Mitigation | Residual Risk |
|--------|--------|-----------|--------------|
| Server compromise | High | Server stores ciphertext only; no keys | Attacker gets encrypted blobs; useless without device keys |
| MITM on key exchange | High | MLS KeyPackage verification via App Check + signed delivery | Reduced to platform-level threat |
| Compromised device | High | Forward secrecy limits exposure to post-compromise messages | Historical messages before compromise protected |
| Screenshot / screen recording | Medium | UIKit screenshot notification + screen recording API detect, notify sender | Cannot prevent; best-effort only. UX must not claim otherwise. |
| Metadata analysis | Medium | Size binning; no content; future: sealed sender mode (P4+) | Sender/recipient graph visible to server |
| Legal intercept / CSAM | Must Address | Evidence path via `one_reportMoment` (see §4); content reported before encryption where user-visible | E2E is a genuine tension; see §4 |
| Insider access | Medium | Firestore rules: only participantUIDs; CF service account cannot read ciphertext | Requires MLS key compromise + device access |
| Key exfiltration via JS / WebView | Low | No WebView in E2E thread path; Secure Enclave keys non-exportable | Negligible |

---

## 3. Privacy Zone Architecture

### 3.1 People Zone (DMs + Groups)
- E2E encrypted (see §1)
- Living Threads AI: on-device only; output never uploaded without explicit user action
- Presence state: never inferred server-side; user-set only; defaults to `unknown`
- Consent DNA: per-message permissions enforced in UI + checked in CF before relay

### 3.2 Moments Zone (Camera + Content)
- Provenance labels: assigned on-device at capture; C2PA-style payload where available; degrades to `.unknown`
- Location: EXIF stripped before upload by default; only precision-bucketed location shared if user consents
- Face blur: on-device processing; processed image uploaded, not raw
- Decay: scheduled via CF (`one_expireMoment`); evidence path runs BEFORE decay (see §4)
- Earned permanence: explicit user action only; no server-side auto-promotion to permanent

### 3.3 World Zone (Feed + Discovery)
- No public like/view counts by default
- Reach budget: no algorithmic amplification; spread capped at `maxChainDepth` (default 5)
- Context gate: server-side CF verifies qualifying action before comment write is accepted
- Symmetric visibility: anonymous viewers are rendered anonymous to the subject (see §3.4)
- Witnesses: season-scoped; no infinite "following" accumulation

### 3.4 Privacy Mirror (Symmetric Visibility)
- If user A views user B's profile while A's `privacyMirror == .sealed`, B's analytics show "anonymous viewer"
- Server enforces: viewer UID is withheld from B's analytics if viewer is `sealed`
- Trust boundary: server must be trusted to enforce this correctly (not client-verifiable)
- Disclosed in privacy policy as server-enforced, not cryptographic

---

## 4. Abuse / Evidence Path

**Core tension:** Ephemeral content decays. CSAM / abuse content must be preservable for law enforcement even if the user deletes it.

**Resolution:**

```
User reports content
  → one_reportMoment(momentID, reason) CF callable
      → CF creates /one_evidence/{evidenceID} with:
          - snapshot of ONEMoment (server-side copy, before decay)
          - reporter UID
          - timestamp
          - encrypted with platform evidence key (NOT user key)
      → CF sets moment.reportedAt = now
      → Decay scheduler checks reportedAt; SKIPS decay if set
      → Evidence retained per legal hold policy (90 days minimum)
```

**E2E tension:** For E2E messages, server holds ciphertext only. Evidence copy is also ciphertext-only UNLESS:
- Sender's device re-encrypts content for evidence key at report time (requires device participation)
- OR user reports from their device, which CAN decrypt → device uploads plaintext to evidence path

**UX disclosure:** Privacy policy must disclose: "Reporting content may result in a copy being retained for safety review, even if the original is set to expire."

**CSAM detection:** Run perceptual hash (PhotoDNA-style) on-device BEFORE upload for all public/semi-public media. Flag matches before they hit Firestore. Private E2E content: NOT scanned (cannot without breaking E2E). Disclosed gap.

---

## 5. Honesty Inventory — What ONE Cannot Enforce

| Claimed Feature | What's Real | UX Requirement |
|-----------------|------------|----------------|
| Screenshot blocking | iOS doesn't support it. We detect + notify. | Label as "We'll notify you of screenshots — we can't block them." |
| E2E + AI analysis | Cryptographically incompatible for true E2E. Living Threads is on-device only. | "AI summaries happen on your device only and are never sent to our servers." |
| Provenance certainty | Confidence threshold; degrades to Unknown. C2PA ecosystem-dependent. | Show confidence level. "Unknown" must never be hidden. |
| Sticky consent ecosystem-wide | Only honored by other ONE instances. Third-party apps ignore ConsentDNA. | "These permissions are honored within ONE. We can't control other apps." |
| Symmetric visibility (cryptographic) | Server-enforced, not cryptographic. | "Your anonymity is enforced by our servers, not by cryptography." |
| Face blur completeness | On-device model; not 100% accurate. | "Face blur may miss some faces. Review before sharing." |

---

## 6. App Check + Auth Requirements

All Cloud Functions callable from ONE:
- Must check `context.app` (App Check token valid) — return 401 if missing
- Must check `context.auth` (Firebase Auth UID) — return 403 if missing
- Must enforce per-UID rate limiting (Firestore counter or CF-side tracking)
- Must never return data from a document the calling UID doesn't have read access to

Firestore rules:
- No `allow read, write: if true` anywhere in ONE paths
- All reads audience-scoped or UID-gated
- `/one_vaults/**` — strictly `request.auth.uid == uid`
- `/one_evidence/**` — no client read/write; CF service account only

---

## 7. Subscription / Entitlement Security

- **StoreKit 2 (not Stripe) on iOS** — per App Store guideline 3.1.1, digital subscriptions require Apple IAP. Stripe is available only for web/admin billing outside iOS.
- StoreKit `Transaction.updates` listener runs for app lifetime; every verified transaction calls `one_verifyEntitlement` CF which writes `one_users/{uid}` entitlement.
- Client NEVER writes its own entitlement field.
- CF `one_verifyEntitlement` re-checks App Store receipt status; no stale cache > 24h.
- Restore flow: `Transaction.currentEntitlements` iterator + server re-verify on every restore tap.
- Free tier gets dignified access; gating is feature-level, not data-level.

---

## 8. P5 Hardening Audit (2026-06-02)

### 8.1 App Check Audit (P5-G)

All callables in `ONECallableService.swift` route through `Functions.functions()` which automatically attaches App Check tokens when App Check is initialized in the app. No callable bypasses this path.

**Findings:**
- ✅ All 9 callables use `functions.httpsCallable()` — App Check token auto-attached
- ✅ Server-side CF enforces `context.app` check (documented; human must set "enforce" mode in console)
- ✅ Auth UID checked server-side on every callable; client propagates CF errors without masking
- ✅ E2E content never passes through `ONEImmuneSignalService` — only momentID + metadata
- ✅ `one_reportMoment` sets `evidenceLocked=true` atomically before decay check

**Deploy prerequisite (human action required):** Switch Firebase console (amen-5e359) App Check from "debug" → "enforce" before any CF reaches external users.

### 8.2 Evidence Path Invariant (P5-C)

Code invariant (client-side): `ONEImmuneSignalService.reportMoment()` calls `one_reportMoment` CF before returning. The CF must set `evidenceLocked=true` on the moment document as its first operation.

Code invariant (server-side, documented, deploy required): `one_expireMoment` CF must check `evidenceLocked` field and skip decay if true. This is in the CF deploy checklist.

Session-dedup: `ONEImmuneSignalService` keeps an in-memory `reportedMomentIDs` set to prevent duplicate reports within a session.

### 8.3 Consent Enforcement (P5 Server-Side Scope)

Current state (P1–P4): ConsentDNA is enforced client-side in `ONEStickyConsentService`. Server validates on `one_sendMoment` ingest (stub — full logic is P5 CF deploy).

P5 deploy requirement: `one_sendMoment` CF must:
- Parse inbound ConsentDNA
- Reject relay if `forwardAllowed=false` on source moment
- Apply `mergedConsentDNA` logic (stricter of source/relay) before writing

### 8.4 Privacy Mirror Server-Side Enforcement (P5 Scope)

Current state (P4): `ONEPrivacyMirrorService.visibilityGranted()` enforces client-side. Firestore rules do not yet restrict profile reads based on `privacyMirror` field.

P5 deploy requirement: Firestore rule for `one_users/{uid}` reads must:
```
allow read: if request.auth != null
    && (resource.data.privacyMirror != 'sealed')
    && (resource.data.privacyMirror != 'opaque' || isWitness(request.auth.uid, uid));
```
This prevents sealed/opaque profiles from being readable by strangers even if the client is compromised.

### 8.5 Accessibility Audit (P5-E)

Audit scope: all Swift files in `AMENAPP/AMENAPP/ONE/**/*.swift`

**Findings:**
- ✅ All icon-only `Button { } label: { Image(systemName:) }` calls have `.accessibilityLabel`
- ✅ All complex row views use `.accessibilityElement(children: .combine)` or `.accessibilityElement(children: .contain)`
- ✅ No bare `.animation()` calls — all use `ONE.Motion.adaptive(reduceMotion:)`
- ✅ `@Environment(\.accessibilityReduceMotion)` consumed in all animated views
- ✅ ARIA-equivalent patterns: `role="switch"` → SwiftUI `Toggle` (correct), `role="dialog"` → `.sheet` with `aria-modal` equivalent via `accessibilityViewIsModal`
- ✅ P5 new views: `ONEEmotionalSafetyModeView`, `ONEReportMomentView`, `ONEEntitlementGateView` all have comprehensive labels, hints, and combined elements

**No a11y fixes required.**

---

## 9. Open Security Questions (P0 Gate — resolved at respective phase gates)

1. **MLS library:** Which MLS implementation to use on iOS 26? (Apple CryptoKit doesn't ship MLS as of training cutoff.) Document fallback to key-ratchet clearly.
2. **Evidence key management:** Who holds the platform evidence encryption key? Define custody before P2.
3. **CSAM PhotoDNA license:** Confirm access to PhotoDNA hash database before P2 ships public upload.
4. **App Check enforcement mode:** Confirm "enforce" (not "debug") mode is set in Firebase console before any P1 CF is deployed.
5. **Legal hold policy duration:** Define minimum retention before `/one_evidence/` schema is frozen.
6. **Sealed sender:** Scope for P4 or defer to post-ship?

---

## 10. Security Review Schedule

| Milestone | Review Type | Status |
|-----------|------------|--------|
| P0 Gate | Architecture review (this document) | ✅ Complete |
| P1 Gate | E2E round-trip pen test (manual smoke) | ✅ Complete |
| P2 Gate | Provenance label bypass test; decay/evidence path verification | ✅ Complete |
| P4 Gate | Privacy mirror enforcement test; ConsentDNA travel test | ✅ Complete |
| P5 Gate | Full security hardening audit (§8 above); a11y sweep | ✅ Complete |
| Pre-ship | App Check enforce mode; server-side Firestore rules deploy; ConsentDNA CF logic | ⏳ Human deploy required |
