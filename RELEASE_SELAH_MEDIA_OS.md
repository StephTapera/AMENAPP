# Selah Media OS — Release Checklist

**Feature:** System 18 — Selah Media OS  
**Status:** Conditional GO (8/10 → target 10/10 after this pass)  
**Flag:** `selah_media_os_enabled` (Remote Config)  
**Rollout:** `selah_media_os_rollout_percent` (start at 5)

---

## Pre-Deploy

- [ ] Clean iOS build passes (no errors)
- [ ] TypeScript build passes: `cd Backend/functions && npm run build`
- [ ] Firebase emulator: `firebase emulators:start --only functions,firestore`
- [ ] Run backend tests: `cd Backend/functions && npm test -- selahMedia`
- [ ] Firestore rules validated in emulator
- [ ] Remote Config defaults confirmed: `selah_media_os_enabled = false`, `selah_media_os_rollout_percent = 0`
- [ ] App Check configured for production project

---

## Deploy

```bash
# 1. Functions
firebase deploy --only functions

# 2. Firestore rules
firebase deploy --only firestore:rules

# 3. Firestore indexes (may take 2–5 min to build)
firebase deploy --only firestore:indexes

# 4. Remote Config defaults (set in Firebase Console)
#    selah_media_os_enabled = false
#    selah_media_os_rollout_percent = 0
#    selah_media_os_min_app_version = 1.0.0
#    selah_media_os_kill_reason = ""
```

---

## Smoke Test — Flag OFF

- [ ] Open app, navigate to home
- [ ] Moon button present in toolbar
- [ ] Tap moon button → view immediately dismisses (does not open)
- [ ] Confirm analytics event `selah_feature_flag_blocked` fires in Firebase DebugView
- [ ] No Firestore reads to `selah_media` collection (check Firestore usage)

---

## Enable for 5% Cohort

```
Remote Config:
  selah_media_os_enabled = true
  selah_media_os_rollout_percent = 5
```

- [ ] Selah Media OS opens for ~5% of users
- [ ] Feed loads without errors (check Firestore logs)
- [ ] Memory save creates document in `users/{uid}/selah_memories`
- [ ] Memory save has correct `userId`, no empty string
- [ ] Continuation create has valid `userId` (not empty string)
- [ ] Berean ask returns a response; no hallucinated scripture references
- [ ] Listener errors appear in Xcode console with `[SelahMediaService]` prefix
- [ ] Concierge sheet opens, shows real session duration (not "active")
- [ ] Concierge buttons do NOT appear for nil-action suggestions
- [ ] Session shaping card appears at post 12 (if applicable)
- [ ] Progressive disclosure expands on long-press
- [ ] Level 4 Berean insight streams a response
- [ ] `selah_media_opened` analytics event fires
- [ ] `selah_mode_switched` fires when switching modes
- [ ] `selah_memory_saved` fires after successful save
- [ ] `selah_berean_asked` fires after asking Berean
- [ ] Audit logs appear in `selahAuditLogs` Firestore collection
- [ ] No duplicate memories created for the same media item

---

## Ramp Schedule

| Phase | Rollout % | Duration | Criteria to advance |
|-------|-----------|----------|---------------------|
| Alpha | 5% | 24h | No P0 errors, analytics flowing |
| Beta | 25% | 48h | No critical crashes, memory save working |
| Wide | 50% | 72h | Stable, Berean response quality acceptable |
| Full | 100% | — | Product review sign-off |

---

## Rollback

If critical issues arise:

```
Remote Config:
  selah_media_os_enabled = false
  selah_media_os_kill_reason = "rollback_[reason]"
```

After setting:
- [ ] Verify entry point dismisses immediately for all users
- [ ] Confirm `selah_feature_flag_blocked` fires with kill reason
- [ ] Monitor callable error rates drop in Firebase console
- [ ] Do NOT delete Firestore data during rollback (preserve user memories)

---

## Security Checklist

- [ ] App Check enforced on all 6 callables
- [ ] Auth check enforced on all 6 callables
- [ ] Rate limits active on all callables
- [ ] No private text (captions, reflections, prayers) in analytics events
- [ ] Memories only readable/writable by owner (`users/{uid}/selah_memories`)
- [ ] Continuations only readable/writable by owner
- [ ] Audit logs write to `selahAuditLogs` (admin-only read)

---

## Known Deferred Items (Post-Launch)

- Concierge "Group" and "Continue" buttons (currently hidden — no action implemented)
- Trust circle member management UI
- Feed pagination beyond 40 items
- Cross-device badge sync
- Security rule unit tests for selah_media public visibility
