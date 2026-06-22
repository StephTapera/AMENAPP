# Backend Access-Control Matrix

Generated: 2026-06-16
Current branch observed by Git: `app-store-readiness-overnight`
Firebase project alias: `default -> amen-5e359`
Status: Working matrix for Module D. Deploy remains human-gated.

## Baseline

| Area | Observed Source | Status |
|---|---|---|
| Firebase config | `firebase.json` | Firestore rules: `firestore.rules`; indexes: `firestore.indexes.json`; Storage rules: `storage.rules`; RTDB rules: `AMENAPP/database.rules.json`; functions codebases: `default`, `v2triggers`, `creator` |
| Functions runtime | `Backend/functions/package.json` | Node 22 for creator codebase |
| Active Xcode scheme | Xcode | `AMENAPP` |
| Active run destination | Xcode | `iPhone 17 Pro Max (27.0)` |
| Rules deploy | Human-gated | No deploy run by agent |
| Functions deploy | Human-gated | No deploy run by agent |
| Known region constraint | Prior reports + deploy logs | `us-central1` near service ceiling; new functions should target `us-east1` |

## Roles

| Role | Source of Authority | Notes |
|---|---|---|
| Guest | No Firebase Auth | Should only access intentionally public approved content |
| Authenticated | Firebase Auth `uid` | Baseline app user; not sufficient for sensitive collections |
| Verified | Server-derived profile/claims | May access verified-only flows; never client-asserted |
| Private-account follower | Follow graph docs | Required for private profile/post access |
| Conversation participant | Conversation participant list | Required for message read/write |
| Space member/mod/admin | Space membership docs and/or claims | Required for space private content and moderation |
| Church admin | Org/church membership docs and/or claims | Required for church admin actions |
| AMEN moderator/admin/super-admin | Custom claims only | Firestore user-doc `isAdmin` must not be treated as final authority by client-facing callables |
| Backend service account | Admin SDK / Cloud Functions | May write backend-only fields |
| Suspended/deleted/blocked | Backend-derived safety/account state | Must fail closed for writes and interactions |

## Operation Matrix

| Operation | Allowed Roles | Rules Plane | Functions Plane | Tested | Risk / Gap |
|---|---|---|---|---|---|
| Read public profile | Guest/Auth, approved public fields only | Partial | N/A | UNVERIFIED | Confirm public profile partition excludes email, phone, push token, roles, trust, entitlements |
| Read private profile | Owner, approved follower, admin backend | Partial | N/A | UNVERIFIED | Requires private subcollection and no collection-group bypass |
| Create/update own profile | Owner | Partial | Partial | UNVERIFIED | `roleAndSafetyFieldsUnchanged()` blocks privileged fields in top-level user docs |
| Change role/admin/trust/account fields | Backend/admin only | Yes | Partial | UNVERIFIED | Some functions still read user-doc `isAdmin`; prefer custom claims |
| Create post | Authenticated, not suspended/blocked, age-safe | Partial | Partial | UNVERIFIED | Rules contain moderation field guards; full block/private validation not rerun |
| Read public post | Guest/Auth for public approved | Yes | N/A | UNVERIFIED | `firestore.rules` allows unauthenticated public reads by policy; human T&S decision remains open |
| Read private post | Owner/follower/member | Partial | N/A | UNVERIFIED | Needs emulator coverage for private-account access and blocked pair denial |
| Comment/reply | Auth, allowed audience, not blocked | Partial | Partial | UNVERIFIED | Verify server-side block enforcement and moderation fail-close before deploy |
| Message | Conversation participant only | Yes | Partial | UNVERIFIED | Prior rules note fixed `participantIds` fallback; emulator tests not run in this pass |
| Follow/block | Auth, self-owned relationship writes | Partial | Partial | UNVERIFIED | Block must suppress messages/comments/follows/notifications in both planes |
| Report content | Auth create-only; mods/admin read | Partial | Partial | UNVERIFIED | NCMEC/legal gate remains blocking for CSAM workflow |
| Upload media | Owner/quarantine first | Yes | Partial | UNVERIFIED | Legacy profile/church/org paths still allow direct/public reads; quarantine deploy gate remains |
| Use AI/Berean | Auth + App Check + capability manifest | Partial | Partial | UNVERIFIED | Streaming and sensitive-context gates require deployed functions and evals |
| Create/moderate space | Member/admin with server authz | Partial | Partial | UNVERIFIED | Verify owner checks and entitlement checks in callables |
| Read reports/moderation/admin data | Moderator/admin/backend only | Yes | Partial | UNVERIFIED | Client-facing reads should be denied except explicit claim-gated views |
| Change entitlements/subscriptions | Backend/payment verifier only | Yes | Partial | UNVERIFIED | Stripe vs IAP policy remains RED; client entitlement writes denied by rules |
| Delete account/export data | Self requests; backend executes | Partial | Partial | UNVERIFIED | Live deletion/export jobs are human-gated |
| Send notifications | Backend only | N/A | Partial | UNVERIFIED | Payload privacy and block suppression need emulator/function test run |

## Field Partitioning Source of Truth

| Resource | Client-Writable | Immutable After Create | Backend-Only |
|---|---|---|---|
| `users/{uid}` | display name, bio, public avatar refs, user preferences | `uid`, `createdAt` | `email`, `phone`, `fcmToken`, `isAdmin`, `role`, `safety`, `trustScore`, `accountStatus`, `entitlements`, `subscriptionStatus` |
| `posts/{postId}` | text/body, media refs, audience/privacy, client metadata allowlist | `ownerUid`/`authorId`, `createdAt` | `moderationStatus`, `safetyLabels`, counters, `rankScore`, review timestamps |
| `posts/{postId}/comments/{commentId}` | body/text, parent/thread refs | `authorUid`, `createdAt` | `moderationStatus`, `safetyStatus`, `guardianVerdict`, moderation decision fields |
| `conversations/{id}/messages/{id}` | user-authored message body and attachments | `senderUid`, `createdAt`, conversation id | assistant/system role messages, moderation/safety fields, delivery fanout fields |
| `reports/{id}` | reporter, target, reason, description | reporter uid, target id, createdAt | moderation status, evidence vault refs, NCMEC submission status, reviewer/audit fields |
| `users/{uid}/bereanMemory/{entryId}` | none direct | N/A | All writes via Cloud Functions only |
| `entitlements/subscriptions/transactions` | none direct | N/A | All writes via payment verifier/backend only |

## Current P0/P1 Findings From This Pass

| ID | Lane | Severity | Finding | Action |
|---|---|---|---|---|
| D-IDENTITY-001 | Green source, Yellow deploy | P0 | `Backend/functions/src/globalResilience/trustScoring.ts` authenticated callers but accepted `data.userId` for `evaluateTrustProfile` and `detectRiskPatterns`. | Source patched to self-only with admin-claim override; deploy `functions:creator:evaluateTrustProfile` / `functions:creator:detectRiskPatterns` only after TypeScript and tests pass. |
| D-ADMIN-001 | Yellow/Red | P1 | Some backend admin checks read Firestore user-doc `isAdmin` (for example `digestBuilder.ts`, `crisisBulletins.ts`). This is weaker than server-verified custom claims. | Migrate admin gates to custom claims or document a deliberate server-only mirror policy. |
| D-STORAGE-001 | Yellow | P1 | `storage.rules` keeps public reads for `uploads/approved`, organization media, church media, and event media. This may be intended CDN behavior, but it is not linked to Firestore visibility/status. | Add linked-doc visibility checks or document product/T&S approval; deploy gated. |
| D-STORAGE-002 | Green source, Yellow deploy | P1 | `profilePhotos/{uid}/{photoId}` still allows direct owner writes outside the quarantine-first path. | Lock to Cloud Functions after quarantine pipeline deployment is confirmed live. |
| D-RULES-TEST-001 | Yellow | P0 | Firestore/Storage emulator tests were not run in this pass. | Human or agent with emulator should run the exact command in `FIREBASE_RULES_AND_FUNCTIONS.md`. |

## Verification Commands

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
npm --prefix Backend/functions run build
firebase emulators:exec --project amen-5e359 --only firestore,functions,storage "cd Backend/rules-tests && npm test"
```

No deploy command belongs in automated execution. All deploys remain in `DEPLOY_PLAN.md`.
