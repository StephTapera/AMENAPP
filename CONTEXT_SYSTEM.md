# AMEN Universal Migration & Context System — Architecture

**Status: Wave 5 complete (2026-06-10). All feature flags default OFF.**
**Canonical contracts: [CONTRACTS.md](CONTRACTS.md). Do not duplicate the type definitions below — summarize and link.**

---

## Table of Contents

1. [One Object, Many Views](#1-one-object-many-views)
2. [§3.3 Tier Table](#2-33-tier-table)
3. [Faith Consent Flow](#3-faith-consent-flow)
4. [Aegis Capabilities C59 & C60](#4-aegis-capabilities-c59--c60)
5. [Wave Map](#5-wave-map)
6. [Feature Flags](#6-feature-flags)
7. [.amen v0.1 Format](#7-amen-v01-format)
8. [Open Gaps & Human Deploy Steps](#8-open-gaps--human-deploy-steps)

---

## 1. One Object, Many Views

There is exactly **one profile primitive**: the **ContextStore**, which is composed of two collections:

- `facets[]` — the only writable surface. Each `ContextFacet` carries a category, a machine key, a structured value, a visibility setting, an encryption tier, and a provenance record.
- `snapshots[]` — append-only time-series. Each `ContextSnapshot` contains an immutable copy of facet states at the moment it was taken.

**Everything else is a projection, never a second store:**

| Projection | What it renders | Source |
|---|---|---|
| IdentityBlueprint | The user's public-facing profile compiled from Tier-C/public facets | `facets[]` filtered by visibility |
| PersonalOperatingManual | A self-authored reference guide (communication style, work preferences, etc.) | `facets[category = communication, work, values, ...]` |
| LifeCapsule | Long-form narrative export of the user's history/growth | `facets[]` + `snapshots[]` delta view |
| ContextQR | Scannable public context card for community introduction | `facets[visibility = public]` only; blocked for minors (C60) |
| .amen file | Portable signed export for import into another AMEN account | `facets[visibility = public OR explicitly checked]`, no Tier-P |

A second store, a parallel schema, or a denormalized facet copy is a **hard reject** (CONTRACTS.md §1).

**Canonical types** (frozen in `AMENAPP/ContextStore/ContextStoreModels.swift`, do not re-define):
`FacetCategory` (13 cases), `Visibility` (5 cases), `EncryptionTier` (S/C/P), `FacetSource` (5 cases), `StructuredFacetValue` (tagged union), `Provenance`, `ContextFacet`, `ContextSnapshot`, `ContextTierTable`.

---

## 2. §3.3 Tier Table

Tier is **derived from category** via `ContextTierTable.tier(for:key:)` — never set per-facet by convention. The Firestore rules layer and the client write path both enforce a match between the stored `tier` field and the table output.

| Category | Tier | Server-readable | Notes |
|---|---|---|---|
| interests | C | Yes | |
| values | C | Yes | |
| goals | C | Yes | |
| skills | C | Yes | |
| communities | C | Yes | |
| communication | C | Yes | |
| learning | C | Yes | |
| current_focus | C | Yes | |
| work | C | Yes | |
| faith_journey (general) | C | Yes | Only after faith consent screen |
| faith_journey `*.areas_needing_support` | **P** | **No** | Key-level override; most sensitive faith facet |
| relationships | **P** | **No** | Categories only — never contacts/names |
| family | **P** | **No** | |
| health | **P** | **No** | |

**Tier semantics:**
- **S** — server-readable sensitive (encrypted at rest, system-processable; reserved for future use)
- **C** — confidential, server-readable for declared features only (matching, feed init, introductions)
- **P** — private, **never server-readable**; client-only projections; never appears in CF payloads, logs, or analytics

### Admin-SDK server-read invariant

Cloud Functions use the Firebase Admin SDK, which bypasses Firestore security rules. **Tier-P confidentiality from Cloud Functions is therefore enforced in CF code, not in rules.** Every callable that touches facets must filter out documents where `tier === 'P'` (or recompute the tier from category/key) before doing anything with them. The `exportAmenFile` callable additionally re-derives tier from category+key as a defense-in-depth backstop. This invariant was verified at the Wave 4 audit gate and is documented in CONTRACTS.md §3.

---

## 3. Faith Consent Flow

Faith data (`faith_journey` category) is Tier-C for general facets — meaning it is server-readable for matching and feed features. Because this is sensitive data, a dedicated consent screen gates the first Tier-C write.

**Flow:**

1. User navigates to the Faith Journey Builder (`FaithJourneyBuilderView`).
2. If no prior consent decision exists, `FaithConsentView` is presented full-screen before any data entry.
3. **Accept** — the user's decision is stored client-side. Subsequent faith facets are written as Tier-C and become eligible for community matching and feed personalization.
4. **Decline** — faith facets are kept as Tier-P (local only). Faith-based community matching is disabled. The user can revisit the decision in Settings.

`ContextTierTable.consentGatedCategories` holds the set `[.faith_journey]` (CONTRACTS.md §3). No faith facet may be written at Tier-C without a recorded consent acceptance.

The `*.areas_needing_support` key within `faith_journey` is **always** Tier-P regardless of consent — the key override in `ContextTierTable.tier(for:key:)` fires before the consent check.

---

## 4. Aegis Capabilities C59 & C60

These two capabilities are frozen in `AMENAPP/ContextStore/AegisEnforcementService.swift`. They extend the AMEN Aegis guardian system with context-specific enforcement. See CONTRACTS.md §4 for the authoritative spec.

### C59 — Context Import Injection Defense

All text pasted or uploaded through the Universal Extractor is treated as **inert data** before it reaches the extraction model:

1. The system prompt tells the model that document content is never instructions.
2. Known injection patterns (prompt-injection sequences, jailbreak prefixes) are neutralized in the pre-LLM pass.
3. Extraction output is capped to the `ContextFacet` schema; free-text fields are length-capped.
4. A `SanitizationReceipt` is emitted with a unique `passId` and stored in `Provenance.sanitizationPassId`.

**Fail-closed invariant:** a facet whose `sanitizationPassId` is empty or unverified must never be persisted. `AegisEnforcementService.verifySanitization(_:)` is the gate; it returns `false` for an empty receipt. Manual entry also goes through this path and receives its own receipt from the entry service (Wave 1).

### C60 — Minor Context Constraints (server-enforced)

For accounts where `isMinor == true` (or where age is unknown — unknown age is treated as minor, fail closed):

| Capability | Decision |
|---|---|
| `contextQR` | **Denied** — Context QR is not available for under-18 accounts |
| `faithAreasNeedingSupportServerWrite` | **Denied** — sensitive faith support data stays private on-device |
| `communityMatching` | **Allowed** — but callers MUST route to youth-safe community indexes (enforced server-side) |

`AegisEnforcementService.minorConstraint(for:isMinor:)` is the client-side façade. Server-side enforcement is the authoritative gate for matching and QR (C60 is listed as server-enforced in CONTRACTS.md §4).

---

## 5. Wave Map

Each wave was gated by the orchestrator. Wave 0 froze all shared surfaces; no subsequent wave modified any canonical type, tier table entry, CF signature, or Firestore rule without a contract amendment.

| Wave | Focus | Key files built | Status |
|---|---|---|---|
| **0** | Contracts | `ContextStoreModels.swift`, `AegisEnforcementService.swift`, `ContextStoreRules.txt`, `AMENFeatureFlags` (`context*` flags), `CONTRACTS.md`, `WAVE_PLAN.md` | FROZEN |
| **1** | Store + Manual Entry + Faith Builder | `ContextStoreService`, `AmenPassportView`, `ManualFacetEntryView`, `IdentityBlueprintView`, `FaithJourneyBuilderView`, `FaithConsentView`, `ContextStoreSecurityTests`, `ContextStoreAdversarialTests`; `firestore.rules` integrated | Complete |
| **2** | Berean Migration Interview | `BereanMigrationInterviewPrompt` (FacetCandidate + JSON schema), `BereanMigrationService` (ephemeral candidates, `approveAndPersist` only write path), `BereanInterviewView` | Complete |
| **3** | Universal Extractor + Approval UI | `ContextExtractionService`, `FacetApprovalView`, C59 implementation in `AegisEnforcementService`, `extractContextFacets` CF | Complete |
| **4** | Consumers: Feed, Matching, Introductions | `initializeFeedFromContext` CF, `matchCommunitiesFromContext` CF, `generateIntroduction` CF; Wave 4 audit gate (Tier-P server-read invariant verified) | Complete |
| **5** | Exports: .amen, QR, Operating Manual, Life Capsule | `exportAmenFile` CF, `signAmenExport` CF, `amenExclusionValidator.ts`, `.amen v0.1` JSON schema + example, `OperatingManualView`, `LifeCapsuleView`, `ContextQRView`; `CONTEXT_SYSTEM.md` (this file) | Complete |

### Stage-3 CF Deploy Batch

All six callables must be deployed together in the Stage-3 batch. They share the same region, App Check enforcement, and Tier-P invariant. No callable may go live without the others being present (the iOS client may call any of them after the master flag is turned on).

| Callable | Source file | Wave | Requires secret |
|---|---|---|---|
| `extractContextFacets` | `functions/context/extractContextFacets.ts` | 3 | No |
| `generateIntroduction` | `functions/context/generateIntroduction.ts` | 4 | No |
| `initializeFeedFromContext` | `functions/context/initializeFeedFromContext.ts` | 4 | No |
| `matchCommunitiesFromContext` | `functions/context/matchCommunitiesFromContext.ts` | 4 | No |
| `exportAmenFile` | `functions/context/exportAmenFile.ts` | 5 | No |
| `signAmenExport` | `functions/context/signAmenExport.ts` | 5 | **Yes** — `AMEN_EXPORT_ED25519_PRIVATE_KEY` |

Deploy command (from `Backend/functions/`):
```
firebase deploy --only functions:extractContextFacets,functions:generateIntroduction,functions:initializeFeedFromContext,functions:matchCommunitiesFromContext,functions:exportAmenFile,functions:signAmenExport --project amen-5e359
```

Before deploying `signAmenExport`, the secret must exist:
```
firebase functions:secrets:set AMEN_EXPORT_ED25519_PRIVATE_KEY --project amen-5e359
```
(Provide a PKCS#8 PEM Ed25519 private key. See §8 below.)

---

## 6. Feature Flags

All Context System flags live in `AMENAPP/AMENFeatureFlags.swift` as `@Published private(set)` properties on `AMENFeatureFlags.shared`. They are Remote Config–backed with snake_case RC keys. **All default `false`.**

Nothing in the Context System is user-visible unless `contextSystemEnabled` is `true`.

| Swift property | RC key | Wave | Controls |
|---|---|---|---|
| `contextSystemEnabled` | `context_system_enabled` | master | All context surfaces — the outer gate |
| `contextManualEntryEnabled` | `context_manual_entry_enabled` | 1 | Manual facet entry, Identity Blueprint, Faith Journey Builder |
| `contextBereanInterviewEnabled` | `context_berean_interview_enabled` | 2 | Berean Migration Interview (adaptive onboarding) |
| `contextUniversalImportEnabled` | `context_universal_import_enabled` | 3 | Paste/upload extractor + Approval UI |
| `contextMatchingEnabled` | `context_matching_enabled` | 4 | Feed init, community matching, introduction drafts |
| `contextExportEnabled` | `context_export_enabled` | 5 | .amen export, Personal Operating Manual, Life Capsule |
| `contextQREnabled` | `context_qr_enabled` | 5 | Context QR (public projection); server blocks for minors via C60 |
| `contextCommitmentBridgeEnabled` | `context_commitment_bridge_enabled` | 4 | Turn a Tier-C goal facet into a Commitment Object |

**Turn-on order for production rollout:**
1. Deploy Stage-3 CF batch (§5 above) + set `AMEN_EXPORT_ED25519_PRIVATE_KEY` secret.
2. Enable `context_system_enabled` in Firebase Remote Config.
3. Enable sub-flags one wave at a time; verify each wave in production before enabling the next.
4. `context_qr_enabled` last — requires C60 server enforcement verified end-to-end.

---

## 7. .amen v0.1 Format

The `.amen` file is a **portable, signed, human-first context profile**. It imports the *person* (durable facts about who someone is), never their *content* (messages, posts, media, contacts).

### Document structure

```json
{
  "$schema": "https://amen.app/schemas/amen-context-v0.1.schema.json",
  "version": "0.1",
  "exportedAt": "<ISO-8601>",
  "issuer": "amen.app",
  "subject": { "displayName": "...", "handle": "@..." },
  "facets": [ <AmenFacetV0_1>... ],
  "signature": { "alg": "Ed25519", "keyId": "amen-export-2026-1", "value": "<base64>" }
}
```

Schema published at `demos/context-system/amen-context-v0.1.schema.json`. Example at `demos/context-system/amen-context-example.amen`.

### Inclusion rule

A facet is included in the export iff:
- `visibility === "public"`, **OR**
- its id was explicitly checked by the user at export time.

Tier-P facets are dropped in `exportAmenFile` regardless of the above (the server recomputes tier from category+key as a defense-in-depth backstop).

### Exclusion validator guarantee

`functions/context/amenExclusionValidator.ts` (and its Swift mirror `AmenExclusionValidator`) is a pure, deterministic, unit-tested gate. `exportAmenFile` runs it as a **hard reject** before returning the payload. Any violation aborts the export with `HttpsError("failed-precondition", ...)`.

The validator rejects any payload containing:

| Denylist item | Detection method |
|---|---|
| Message / post structures | Denylisted keys: `messages`, `posts`, `dms`, `thread`, `conversation`, `inbox`, `replies`, etc.; thread-marker text ("On \<date\> \<name\> wrote:"); 3+ consecutive quoted `>` lines |
| Media URLs | `http(s)://` links with media extensions (.jpg, .mp4, .mp3, etc.) or known media hosts (Firebase Storage, YouTube, Cloudinary, etc.) |
| Email addresses | RFC-like email pattern in any string value |
| Phone numbers | 7+ digit telephone patterns in any string value |
| Contact arrays | Denylisted keys: `contacts`, `recipients`, `to`, `cc`, `bcc`, `addressBook`, `phonebook`, `emails`, `phones`, etc.; vCard blocks |

Violations are reported as **path + reason**, never echoing the offending value.

### Signing

`signAmenExport` issues an Ed25519 signature over a canonical serialization of the `amen` document (object keys sorted recursively, no insignificant whitespace, UTF-8). Key id is `amen-export-2026-1`. A future key rotation requires a new id and a new secret.

On import, the receiving AMEN client canonicalizes the received document, verifies the signature against the bundled public key for the given `keyId`. An unknown `keyId` or bad signature sets provenance to "unverified" — the facets are still importable but are routed through `FacetApprovalView` (never auto-imported).

---

## 8. Open Gaps & Human Deploy Steps

These items are not silently closed. Each requires a human action or a live run.

### Human deploy steps

| Step | Action | Blocking |
|---|---|---|
| **Stage-3 CF deploy** | Deploy all 6 callables (see §5 table). `context_system_enabled` must remain OFF until complete. | Yes — nothing is live without the CFs |
| **`AMEN_EXPORT_ED25519_PRIVATE_KEY` secret** | Generate an Ed25519 key pair. Set private key: `firebase functions:secrets:set AMEN_EXPORT_ED25519_PRIVATE_KEY`. Bundle the corresponding public key in the iOS app for client-side signature verification. | Yes — `signAmenExport` fails closed without it |
| **Remote Config flags** | After CF deploy, set `context_system_enabled = true` in Firebase Remote Config (project `amen-5e359`), then sub-flags per wave. See §6 turn-on order. | Yes — flags default OFF |
| **Firestore emulator harness** | The repo has no Firestore emulator harness. Rules in `ContextStoreRules.txt` (integrated into `firestore.rules`) are currently asserted by text-invariant + unit guards only. A human needs to stand up the emulator and run the rules against the test corpus. | Recommended before production rollout |
| **Live bait-transcript run** | 10-persona bait transcripts for C59 injection defense need a LIVE model run to confirm the pre-LLM neutralization holds. Scheduled as the first task of Wave 3 but requires a live CF environment. | Recommended before `contextUniversalImportEnabled = true` |

### Firestore emulator harness

Wave 1 note from RUNLOG.md: "no Firestore emulator harness in repo → rules asserted by text-invariant + unit guards until a human stands up the emulator." The `contextFacets` and `contextSnapshots` collections and their security rules (`isOwner()` read/write, `userApproved == true` + `schemaVersion == 1` required for writes, snapshots append-only) are correct in text but need emulator verification before beta.

### Live bait-transcript run

Wave 2 note from RUNLOG.md: "10-persona bait transcripts need a LIVE model run — scheduled as the FIRST Wave 3 task." This confirms that C59's pre-LLM neutralization pass holds against adversarial input. The test corpus is in `demos/context-system/red-team-report.md`.

### AMEN_EXPORT_ED25519_PRIVATE_KEY secret

`signAmenExport` calls `defineSecret("AMEN_EXPORT_ED25519_PRIVATE_KEY")` and fails closed if the secret is absent or malformed. Key generation:

```sh
# Generate key pair (Node.js)
node -e "
const {generateKeyPairSync} = require('crypto');
const {privateKey, publicKey} = generateKeyPairSync('ed25519', {
  privateKeyEncoding: {type: 'pkcs8', format: 'pem'},
  publicKeyEncoding: {type: 'spki', format: 'pem'}
});
console.log('PRIVATE:\n', privateKey);
console.log('PUBLIC:\n', publicKey);
"
# Set private key as Firebase secret
firebase functions:secrets:set AMEN_EXPORT_ED25519_PRIVATE_KEY --project amen-5e359
# Bundle public key in iOS app for AmenExportService client-side verification
```

---

*Cross-reference: [CONTRACTS.md](CONTRACTS.md) for the canonical frozen contract. [WAVE_PLAN.md](WAVE_PLAN.md) for gate discipline and §11 recon deltas. [AMENAPP/ContextStore/RUNLOG.md](AMENAPP/ContextStore/RUNLOG.md) for build history and incident log.*
