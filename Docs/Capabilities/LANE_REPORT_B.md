# Capabilities v1 — Lane B (BACKEND-CAPS) Report

**Wave 1 — Lane B complete**

Date: 2026-06-13

---

## Items Delivered

| # | Item | File(s) | Commit |
|---|------|---------|--------|
| 1 | `capabilityRegistry_list` callable | `functions/src/capabilities/registry/callables.ts` + `registry/index.ts` | `48e1472f` |
| 2 | PrayerOS 4 callables | `functions/src/capabilities/prayerOS/callables.ts` + `prayerOS/index.ts` | `430d3cab` |
| 3 | `prayerOS_followUpSweep` scheduled | `functions/src/capabilities/prayerOS/scheduled.ts` | `430d3cab` |
| 4 | Scripture reference parser | `functions/src/capabilities/scripture/referenceParser.ts` | `c8d4b4dd` |
| 5 | Scripture 3 callables | `functions/src/capabilities/scripture/callables.ts` + `scripture/index.ts` | `c8d4b4dd` |
| 6 | `seedCapabilities.ts` idempotent seed | `functions/src/capabilities/scripts/seedCapabilities.ts` | `394e8be6` |
| 7 | `tsconfig.capabilities.json` | `functions/tsconfig.capabilities.json` | `a582fb23` |
| 8 | Scripture parser unit tests (65 tests) | `functions/src/capabilities/scripture/referenceParser.test.ts` | `a582fb23` |

---

## Definition of Done — Checklist

- [x] All 7 items complete (not skeletons)
- [x] Scripture parser has ≥40 unit tests passing (65 passing)
- [x] `npx tsc -p functions/tsconfig.capabilities.json --noEmit` exits 0
- [x] All modules export per contract
- [x] Contracts not modified

---

## Key Implementation Notes

### Registry (Item 1)
- `capabilityRegistry_list`: No App Check (picker UI must work before attestation), auth required.
- Queries Firestore `capabilities` where `status == "active"` AND `surfaces array-contains surface`.

### Prayer OS (Items 2–3)
- All 4 callables: App Check enforced, auth required.
- `prayerOS_createCard`: context access check for `prayerHistory` + `messagesMeta` via `resolveContextAccess`; dedupes on subject.displayName if prayerHistory is "allowed".
- `prayerOS_updateCard`: only patches fields present in request; uses Firestore transaction for `completeFollowUp`.
- `prayerOS_listCards`: cursor pagination with `startAfter` doc-ID approach, one-extra fetch for `nextCursor` detection.
- `prayerOS_followUpSweep`: every 15 minutes; marks followUps "prompted" before queuing notification (idempotency guard); writes to `users/{uid}/notificationQueue/{autoId}` for existing notification consumer; also sweeps reminders and advances `nextFireAt` with lightweight rrule heuristic.

### Scripture Parser (Items 4–5)
- Pure TypeScript, zero LLM calls.
- 66-book registry with full names + abbreviations → OSIS codes.
- Multi-word books ("Song of Solomon", "1 Samuel", etc.) matched first via substring scan with word-boundary checks, preventing false positives.
- Single-word books matched via regex with word-boundary enforcement.
- False positives prevented by requiring a known book token before any `N:N` pattern.
- OSIS format: `Rom.6.1-Rom.6.4`, `Jhn.3.16`, `1Co.13`, etc.
- `scripture_getVerses` checks `scriptureCache/{translation}/{osisRef}` first (90-day TTL), then calls API.Bible using `API_BIBLE_KEY` secret (same path as `sanctuary/index.ts`).
- `scripture_searchVerses` tries direct ref parse first, then falls back to `scriptureCatalog` keyword search if the collection exists.

### Seed Script (Item 6)
- `setDoc` only if doc doesn't already exist (checked via `getDoc` first).
- Seeds: `prayer_os`, `scripture_intelligence`, `verse_lookup`.

### TypeScript Config (Item 7)
- `rootDir: "src"` (not `src/capabilities`) to allow the import of `../../contextEngine/resolveContextAccess`.
- Includes both `src/capabilities/**/*.ts` and `src/contextEngine/**/*.ts`.
- Excludes test files from emit.

### Tests (Item 8)
- 65 tests across 9 describe blocks.
- `jest.capabilities.config.js` — separate jest config for capabilities tests, not touching existing jest block in package.json.
- All 65 pass.

---

## Deploy Steps (Human Required)

1. Deploy prayerOS callables + scheduled sweep:
   ```
   firebase deploy --only functions:default:prayerOS_createCard,functions:default:prayerOS_updateCard,functions:default:prayerOS_listCards,functions:default:prayerOS_completeFollowUp,functions:default:prayerOS_followUpSweep
   ```
2. Deploy scripture callables:
   ```
   firebase deploy --only functions:default:scripture_detectReferences,functions:default:scripture_getVerses,functions:default:scripture_searchVerses
   ```
3. Deploy registry callable:
   ```
   firebase deploy --only functions:default:capabilityRegistry_list
   ```
4. Run seed script against staging:
   ```
   npx ts-node -P functions/tsconfig.capabilities.json functions/src/capabilities/scripts/seedCapabilities.ts
   ```
5. Ensure `API_BIBLE_KEY` secret is set in Firebase project.
