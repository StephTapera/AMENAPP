# AMEN Living Intelligence — Contract Reference

**Owner:** Living Intelligence Agent 1 (Engine)
**Date:** 2026-06-05
**Status:** FROZEN — changes require version bump + all-agent sign-off

---

## 1. IntelligenceCard Type

Every card surfaced in a user's brief must conform to this shape.
The canonical validator is `functions/intelligence/contracts.js → assertCard(card)`.

```typescript
type TruthLevel    = 'VERIFIED' | 'CHURCH_CONFIRMED' | 'COMMUNITY_CONFIRMED' | 'DEVELOPING';
type ActionRung    = 'NOTICE' | 'PRAY' | 'LEARN' | 'DISCUSS' | 'GIVE' | 'SHOW_UP' | 'START';
type BackingKind   = 'CHURCH' | 'ORG' | 'EVENT' | 'PRAYER_REQUEST' | 'STUDY' | 'NEED';
type Tier          = 'SPIRITUAL' | 'COMMUNITY' | 'FAMILY' | 'LOCAL' | 'GLOBAL';

interface IntelligenceAction {
  rung:    ActionRung;
  label:   string;         // Human-readable button label
  handler: string;         // CF callable function name (must be real)
  target:  string;         // Entity ID the action targets
}

interface BackingEntity {
  kind:     BackingKind;
  id:       string;        // Must resolve to a real Firestore doc
  verified: boolean;       // Must be true — assertCard throws if false
}

interface Formation {
  finite:            true;   // Always true — briefs are always finite
  spectacleCounters: false;  // Always false — no engagement counters
  lamentFrame?:      boolean;
  loopParentId?:     string; // Prior action ID this card follows up on
}

interface Geo {
  lat:    number;  // Rounded to 2dp (coarse ~1km)
  lng:    number;  // Rounded to 2dp (coarse ~1km)
  coarse: true;    // Always true — precise location prohibited
}

interface IntelligenceCard {
  id:            string;            // Stable: `${kind}_${entityId}_${userId}`
  tier:          Tier;
  title:         string;
  summary:       string[];          // 1-3 bullets, Berean-generated, real citations only
  backingEntity: BackingEntity;     // REQUIRED — no card renders without verified entity
  truthLevel:    TruthLevel;
  matchScore?:   number;            // 0-100
  matchReasons?: string[];
  actions:       IntelligenceAction[]; // Ordered commitment ladder — non-empty
  rankScore:     number;            // 0-100
  rankReasons:   string[];          // REQUIRED — legible human-readable strings
  geo?:          Geo;               // Coarse only — never precise
  formation:     Formation;
  source?:       string;            // REQUIRED for GLOBAL tier cards
  createdAt:     number;            // Epoch ms
  expiresAt:     number;            // Epoch ms — must be > createdAt
}
```

---

## 2. Formation Invariants

These 7 invariants are enforced by `formationGovernor.js`. Any card violating an invariant
is rejected or corrected before the brief is written to Firestore.

| # | Invariant | Enforcement |
|---|-----------|-------------|
| FI-1 | Briefs are finite: max 7 cards per brief | `enforceBriefCap(cards)` |
| FI-2 | DEVELOPING cards are always demoted (never first) | `enforceBriefCap` sorts DEVELOPING to end |
| FI-3 | No spectacle counters on any card | `stripSpectacleCounters(card)` |
| FI-4 | Geo is coarse-only (2dp, ~1km precision) | `enforceGeo(card)` |
| FI-5 | Political content restricted to PRAY/GIVE/SHOW_UP/DISCUSS | `enforcePoliticsFilter(card)` |
| FI-6 | `backingEntity.verified === true` required | `assertCard(card)` throws |
| FI-7 | Prior SHOW_UP/GIVE actions must have follow-up card | `assertLoopClosure(cards, priorActions)` |

**Additional assertCard invariants:**
- `rankReasons` must be non-empty
- `formation.finite === true`
- `formation.spectacleCounters === false`
- `summary.length <= 3`
- GLOBAL tier cards must have `source`
- `actions` non-empty
- `expiresAt > createdAt`
- DEVELOPING cannot have `rankScore > 80`
- `geo.coarse === true` if geo present

---

## 3. Firestore Collections

### `intelligence_briefs/{userId}`
Brief document written by `digestBuilder.buildUserBrief()`.
Expires 12 hours after generation.

```
{
  userId:     string,
  cardIds:    string[],           // IDs of cards in this brief
  cardCount:  number,
  generatedAt: number,            // Epoch ms
  expiresAt:  number,             // Epoch ms (now + 12h)
  builtAt:    ServerTimestamp,
}
```

Sub-collection: `intelligence_briefs/{userId}/audit/{auditId}`
Used by `enforceDigestCadence` to cap rebuilds at 2/day.

### `intelligence_cards/{cardId}`
Individual card document. CardId is stable: `${kind}_${entityId}_${userId}`.

Fields: all IntelligenceCard fields + `userId` + `writtenAt` (ServerTimestamp).

### `intelligence_actions/{userId}/actions/{actionId}`
User action records for loop-closing.

```
{
  cardId:       string,
  rung:         ActionRung,
  targetId:     string,
  loopParentId: string,   // card or prior action being followed up
  userId:       string,
  createdAt:    ServerTimestamp,
}
```

### `opportunity_graph/{nodeId}`
Internal graph nodes. Clients cannot read/write. CF Admin SDK only.

```
{
  type:     string,    // 'church' | 'user' | 'need' | 'event' | 'opportunity'
  optIn:    boolean,   // for user nodes — opt-in to matching
  weight:   number,    // match scoring weight
  updatedAt: ServerTimestamp,
}
```

Sub-collection: `opportunity_graph/{nodeId}/edges/{edgeId}`

```
{
  type:         'supplies' | 'needs' | 'attends' | 'volunteers',
  targetNodeId: string,
  weight:       number,
  createdAt:    ServerTimestamp,
}
```

### `church_pulse/{churchId}`
Aggregate church health data. Read by members, pastors, admins only. CF writes only.

---

## 4. Cloud Function Callable Signatures

All callables are gen-2 (`firebase-functions/v2/https` `onCall`).

### `getIntelligenceBrief`

**Secrets:** `BEREAN_LLM_KEY`, `ANTHROPIC_API_KEY`
**Auth:** Required

Request: `{}` (no params — brief is always for the authenticated user)

Response:
```typescript
{
  brief:       object,              // intelligence_briefs doc
  cards:       IntelligenceCard[],  // resolved card objects
  generatedAt: number,              // epoch ms
  fromCache:   boolean,             // true if returned existing fresh brief
}
```

Errors: `unauthenticated`, `internal`

### `recordIntelligenceAction`

**Auth:** Required

Request:
```typescript
{
  cardId:       string,      // the card the user acted on
  rung:         ActionRung,  // which rung was activated
  targetId:     string,      // entity being acted upon
  loopParentId?: string,     // optional: override loop parent id
}
```

Response:
```typescript
{
  success:      boolean,
  actionId:     string,  // Firestore doc ID of the created action
  loopParentId: string,  // the loop parent that was recorded
}
```

Errors: `unauthenticated`, `invalid-argument`

### `buildDailyIntelligenceBriefs` (Scheduled)

**Schedule:** `0 7,19 * * *` UTC (7am + 7pm)
**Secrets:** `BEREAN_LLM_KEY`, `ANTHROPIC_API_KEY`
**Memory:** 512 MiB
**Timeout:** 540s

Processes all users with `intelligenceOptIn === true` in batches.
Max 50 concurrent brief builds per batch.

---

## 5. callModelRouter Task Reference

All tasks route through `functions/intelligence/callModelRouter.js → callModel()`.

| Task | Provider | Input | Output |
|------|----------|-------|--------|
| `intelligence.summarize` | Berean (fallback: Anthropic/Claude) | `{ title, rawContent, scriptureRefs }` | `string[]` (1-3 bullets) or `null` |
| `intelligence.classify_need` | Anthropic/Claude | `{ text }` | `{ needType, confidence, urgency }` or `null` |
| `intelligence.match` | Anthropic/Claude | `{ entityKind, entityData, userProfile }` | `{ matchScore, matchReasons }` or `null` |
| `intelligence.world_response` | Anthropic/Claude | `{ title, source, rawContent }` | `{ known[], contested[], howToRespond[] }` or `null` |

**Failure policy:** All tasks fail closed — return `null` on any error. Never fabricate.
`intelligence.world_response` requires a non-empty `source` field; returns `null` otherwise.

---

## 6. Ranking Formula

`rankCard(card, context)` in `functions/intelligence/rankingBrain.js`.

```
rankScore = base + boosts - penalties  (clamped 0-100)

base:
  actionabilityScore(actions) × 30   — higher rungs = more actionable
  truthLevelScore(truthLevel) × 20   — VERIFIED=4, CHURCH_CONFIRMED=3, COMMUNITY_CONFIRMED=2, DEVELOPING=1
  tierScore(tier) × 10               — SPIRITUAL→1.0 ... GLOBAL→0.2

boosts:
  +15  followedChurchIds includes card's churchId   → "Your church"
  +15  loopParentId in priorActions                 → "Follows up on your prior action"
  +10  seasonOfLife matches card.matchReasons       → "Relevant to your life stage"
  +10  liturgicalSeason alignment                   → "Seasonally relevant"
  +10  location within 10km of card.geo             → "Near you"
  +8   userCapacity === 'available'                 → "You have capacity to act now"

penalties:
  -30  truthLevel === DEVELOPING
  -5   lamentFrame with no disaster context
  0    GLOBAL + missing source → card rejected (score 0, reason string returned)
```

---

## 7. Secrets Required

| Secret | Used by | Purpose |
|--------|---------|---------|
| `BEREAN_LLM_KEY` | `callModelRouter`, `v2intelligenceFunctions` | Berean AI summarization |
| `ANTHROPIC_API_KEY` | `callModelRouter`, `v2intelligenceFunctions` | Claude classification, matching, world response |

Both secrets must be provisioned in Secret Manager before deploying `v2intelligenceFunctions.js`.

---

## 8. Security Rules Summary

See `firestore.rules` — Intelligence collections appended at end.

| Collection | Client Read | Client Write |
|------------|-------------|--------------|
| `intelligence_cards/{cardId}` | Owner only | CF only |
| `intelligence_briefs/{userId}` | Owner only | CF only |
| `intelligence_actions/{userId}` | Owner only | CF only |
| `opportunity_graph/{nodeId}` | None | CF only |
| `church_pulse/{churchId}` | Members, pastors, admins | CF only |
