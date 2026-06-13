# Capabilities v1 — Lane A Report (BACKEND-CONTEXT)

**Lane:** A — Context Engine  
**Branch:** feature/berean-island-w0  
**Completed:** 2026-06-13  

---

## Items Delivered

| Item | File | Commit | Status |
|---|---|---|---|
| 1 | `functions/src/contextEngine/resolveContextAccess.ts` | 48e1472f | DONE |
| 2 | `functions/src/contextEngine/callables.ts` | 48e1472f | DONE |
| 3 | `functions/src/contextEngine/index.ts` (skeleton replaced) | 48e1472f | DONE |

---

## resolveContextAccess.ts

Internal (non-callable) module implementing `resolveContextAccess(input: ResolveAccessInput): Promise<ResolveAccessOutput>`.

**Policy matrix:**
- `"always"` → `allowed`
- `"whileUsing"` + `foreground` → `allowed`
- `"whileUsing"` + `background` → `denied`, reason `backgroundDenied`
- `"askEveryTime"` → `promptRequired`
- `"never"` (or missing doc) → `denied`, reason `notGranted`
- `"calendar"` or `"location"` → `denied`, reason `notYetSupported` (regardless of stored policy)

**Audit behavior:** writes one `contextAuditLog` entry per source via Firestore batch write. Failure caught and logged — never re-thrown. Each call generates a unique `requestId` via `crypto.randomUUID()`.

---

## callables.ts

Three App Check-gated callables:

**`contextEngine_getGrants`** (no App Check)
- Auth required
- Reads `users/{uid}/contextGrants/` collection
- Returns all 8 `ContextSource` values; missing docs defaulted to policy `"never"`, version 0

**`contextEngine_setGrant`** (App Check enforced)
- Auth required
- Validates source and policy against frozen enum values
- Upserts grant doc; uses `FieldValue.increment(1)` for atomic version bump
- Uses `{ merge: true }` to preserve `grantedAt` on subsequent updates

**`contextEngine_getAuditLog`** (no App Check)
- Auth required
- pageSize: default 20, clamped to max 50
- Ordered by `at` desc
- Cursor pagination via `startAfter` doc ID → resolves to Firestore snapshot before querying
- Returns `nextCursor` only when page is full

---

## index.ts

Exports all three callables and `resolveContextAccess`. Replaces Wave 0 skeleton.

---

## Definition of Done Checklist

- [x] All 3 files implemented (not skeletons)
- [x] resolveContextAccess handles all 8 sources + both invocationTypes correctly
- [x] Device-level sources (calendar, location) always denied with `notYetSupported`
- [x] Audit log written on every resolve call (batch write, failures caught + logged)
- [x] All 3 callables implemented with proper auth checks
- [x] getGrants fills all 8 sources even when no docs exist
- [x] setGrant uses FieldValue.increment(1) for atomic version
- [x] getAuditLog paginated with cursor, max 50
- [x] TypeScript: 0 errors (verified with `npx tsc --noEmit`)
- [x] No new npm dependencies (firebase-admin/firebase-functions only)
- [x] No files touched outside `functions/src/contextEngine/`
