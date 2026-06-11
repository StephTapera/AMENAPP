# AMEN Universal Migration & Context System — Contracts

## Finalized Contracts (Wave 0)

### 1. Facet Schema (Canonical)
- **Encryption Tiering:** S (server-readable), C (confidential), P (private/client-only).
- **Provenance:** MUST include sanitizationPassId (Aegis C59).
- **User Approval:** MUST be true for Firestore write.

### 2. Tier Table
| Category | Tier | Server | Notes |
|---|---|---|---|
| interests/values/goals/skills/communities/communication/learning/focus | C | Yes | Feed/Match |
| relationships/family/health | P | No | Client-only |
| faith_journey | C | Yes | Church matching; Requires consent |
| faith_journey: areas_needing_support | P | No | Always P |

### 3. Aegis Capabilities (Registry)
- **C59:** Context Import Injection Defense. (Pre-LLM sanitization, inert-data wrapping).
- **C60:** Minor Context Constraints. (Server-side constraint for <18 accounts).

### 4. Firestore Security Rules
- **/contextFacets/{userId}/facets/{facetId}**: Read/Write (owner only). Server (Admin SDK) read Tier C only.
- **/contextSnapshots/{userId}/snapshots/{snapshotId}**: Read/Write (owner only).

### 5. Function Signatures
- `extractContextFacets`, `generateIntroduction`, `initializeFeedFromContext`, `matchCommunitiesFromContext`, `exportAmenFile`, `signAmenExport`
