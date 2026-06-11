# AMEN Universal Migration & Context System — CONTRACTS (Wave 0)

**STATUS: FROZEN 2026-06-10.** No Wave 1+ agent may modify a type, enum case, the
tier table, a Firestore rule, or a CF signature below without a contract amendment
(halts all parallel work until re-frozen). Source of truth for code:
`AMENAPP/ContextStore/ContextStoreModels.swift`, `AegisEnforcementService.swift`,
`ContextStoreRules.txt`, and `AMENAPP/AMENFeatureFlags.swift`.

## 1. One object, many views
One primitive: **ContextStore** = `facets[]` (only writable surface) + `snapshots[]`
(append-only). IdentityBlueprint / PersonalOperatingManual / LifeCapsule / ContextQR /
.amen are **projections**, never separate stores. A second store / parallel schema /
denormalized facet copy is a hard reject.

## 2. Canonical types (frozen)
`FacetCategory` (13 cases), `Visibility` (5), `EncryptionTier` (S/C/P), `FacetSource` (5),
`StructuredFacetValue` (text | list | faithJourney | communicationStyle | relationshipCategory),
`Provenance`, `ContextFacet`, `ContextSnapshot`. See `ContextStoreModels.swift`.

Invariants:
- New facet default visibility = `private`; default approval = `false`.
- `ContextFacet.tier` MUST equal `ContextTierTable.tier(for: category, key:)`. The client
  write path fails loudly on mismatch; rules require `tier in ['S','C','P']` + `userApproved`.
- Snapshots are immutable & append-only.

## 3. Tier table (law) — `ContextTierTable`
| Category | Tier | Server-readable |
|---|---|---|
| interests, values, goals, skills, communities, communication, learning, current_focus, work | C | Yes |
| faith_journey (general) | C | Yes — **after faith consent screen** |
| faith_journey `*.areas_needing_support` | **P** | No |
| relationships, family, health | **P** | No |

Rules: tier is derived from category (+ the one faith key override); agents may not set it
per-facet. Faith categories require the dedicated consent screen before the first Tier-C
faith write; declining keeps them Tier P and disables faith matching only. Tier-P facets
never appear in CF payloads, logs, or analytics.

**Server-read invariant:** Admin SDK bypasses Firestore rules, so Tier-P confidentiality
from Cloud Functions is enforced in CF CODE — server functions must never query facets
where `tier == 'P'`. Verified at the Wave 4 audit gate.

## 4. Aegis capabilities (frozen) — `AegisEnforcementService.swift`
- **C59 Context Import Injection Defense** — inert-data wrapping, pre-LLM pattern
  neutralization, schema/length output capping, `SanitizationReceipt` → `Provenance.sanitizationPassId`.
  A facet with an empty receipt id must never persist. Fails closed.
- **C60 Minor Context Constraints** (server-enforced) — under-18: Context QR denied,
  faith "areas needing support" forced Tier P, matching routed to youth-safe indexes.
  Unknown age treated as minor (fail closed).

## 5. Feature flags (frozen) — `AMENFeatureFlags`
`contextSystemEnabled` (master) + `contextManualEntryEnabled`, `contextBereanInterviewEnabled`,
`contextUniversalImportEnabled`, `contextMatchingEnabled`, `contextExportEnabled`,
`contextQREnabled`. RC keys `context_*_enabled`, all default **false**. Nothing user-visible
unless the master flag is true.

## 6. Firestore (frozen) — `ContextStoreRules.txt`
Collections `contextFacets/{userId}/facets/{facetId}`, `contextSnapshots/{userId}/snapshots/{snapshotId}`.
Owner-only; writes require `userApproved == true` + `schemaVersion == 1`; snapshots append-only;
deny-by-default elsewhere. Integrated into `firestore.rules` + emulator-tested in Wave 1.

## 7. Cloud Functions (signatures frozen)
All `onCall`, `enforceAppCheck: true`, region `us-central1`, project `amen-5e359`.
Tier-P inputs/outputs forbidden in every signature below.

| Function | Wave | Input → Output (shape) |
|---|---|---|
| `extractContextFacets` | 3 | `{ text, sourceLabel, sanitizationPassId }` → `{ candidates: FacetCandidate[] }` (structured output; free-text length-capped) |
| `generateIntroduction` | 4 | `{ communityId, facetKeys[] (public/groups only) }` → `{ draft: string }` (never auto-posts) |
| `initializeFeedFromContext` | 4 | `{ }` (reads owner Tier-C facets server-side) → `{ written: bool }` (writes via Hey Feed prefs) |
| `matchCommunitiesFromContext` | 4 | `{ minor: bool }` → `{ matches: [{id, type, explanation}] }` (youth-safe filtered for minors) |
| `exportAmenFile` | 5 | `{ facetIds[] }` → `{ amen: AmenContextV0_1 }` (visibility-filtered + exclusion-validated) |
| `signAmenExport` | 5 | `{ amen }` → `{ signature: {alg:"Ed25519", keyId, value} }` |

## 8. .amen v0.1 (frozen)
Open JSON spec; exports include only `public` facets + explicitly-checked ones; a unit-tested
exclusion validator rejects any payload containing messages/posts/media URLs/emails/phones/contact
arrays; Ed25519 signatures; import routes through the Approval UI. Schema published in Wave 5.

## 9. Hard constraints (apply to every agent, every wave)
Flag OFF by default · contracts frozen · HTML demo before SwiftUI · three-strikes stop ·
no content import (enforced in code) · tier table is law · approval before persistence ·
Aegis on every import path · reuse don't duplicate · no spiritual ranking · Firestore deny-by-default ·
minors get the constrained path.
