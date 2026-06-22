# AMEN — "10/10 GO" Runbook (2026-06-22)

Status at authoring: **code-side GO**. iOS build GREEN (0 errors, 33s) at commit `e7415fe7`
(on top of peer-verified GREEN `920fa652`). All remaining items below are **human/gated**
(deploys are forbidden for agents per CLAUDE.md; legal is human; archive needs a quiet tree).

This session closed the last two code items:
- **C-8** medical hard-refuse (BereanConstitutionalIntelligence.swift) — clinical-advice
  requests now refuse regardless of any disclaimer flag. iOS build GREEN.
- **C-13** RSVP soft-delete (spaceEvents.ts) — cancel soft-cancels + adds `userId` so the
  account-deletion cascade purges it. `tsc` clean. **Needs deploy (see §1).**

Commit: `e7415fe7` (branch `feature/volunteer-board-wave0`). 2 files only.

---

## §1 — DEPLOYS (human, from repo root only; see CLAUDE.md Firebase rules)

> NEVER `firebase deploy` bare or `--only functions` untargeted. Always repo root, targeted
> codebase. Log to `deploy-logs/`. us-central1 is at 999/1000 — UPDATES to existing funcs are
> fine; NEW funcs go to us-east1 + Interim Region Table.

### 1a. My C-13 backend change (update, not new — us-central1 OK)
```sh
cd Backend/functions && npm run build        # regenerate lib/ from src (tsc)
cd ../..                                       # back to repo root
firebase deploy --only functions:creator:rsvpToSpaceEvent 2>&1 | tee deploy-logs/c13-rsvp-$(date +%Y%m%d).log
```

### 1b. Carried-over deploys (from prior readiness memo — verify still needed)
- Backend fixes already COMMITTED in code, need deploy: prayer-search guard
  (`onPostCreated.ts`), DM-video fail-closed (`moderateUGC.js`).
- Pending CF batches: aegis (5), spaces (8), calm/rhythm (10), churchSearch/provenance/selah (3).
- `firestore.rules` deploy: `firebase deploy --only firestore:rules`
- RemoteConfig flag seeding (Trust/Transparency Wave flags currently OFF by design — confirm
  intended launch state before flipping any ON).

## §2 — LEGAL / DPO (human, blocking for App Store + law)
- NCMEC CyberTipline wiring + CSAM ESP registration (18 U.S.C. §2258A).
- Firebase Analytics tracking classification confirm vs `PrivacyInfo.xcprivacy`
  (NSPrivacyTracking=false must stay consistent — verified consistent in code).
- IAP terms surface (if Stripe-hosted, confirm link present in-app).

## §3 — BUILD → ARCHIVE → VALIDATE (human, quiet tree)
1. Quiet the tree (no other agents building — shared build.db corruption risk).
2. Canonical build (per CLAUDE.md):
   ```sh
   xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
     -clonedSourcePackagesDirPath ./SourcePackages.nosync \
     -derivedDataPath ./DerivedData.nosync
   ```
   (Agent BuildProject already returned BUILD SUCCEEDED at `e7415fe7`; this is the release/device pass.)
3. Strip `.appex` codesign detritus if it recurs: `xattr -cr` on the extension
   (com.apple.FinderInfo re-added by Desktop fileprovider — known, not a code defect).
4. Xcode → Archive → Organizer → Validate App → upload to ASC.

## §4 — NOTE: dangling commit recovery
Commit `4b3256d6` (orphaned, in reflog) holds index-only staged work from concurrent agents
that was sitting in the shared default index. If any peer's staged-but-not-on-disk change is
missing, recover from `git show 4b3256d6`. Peers' on-disk work was untouched (629 files still
modified in WT).

---

## What is verified GREEN (code-side)
- 10/10 quality-audit P0s CONFIRMED at HEAD (media safety gate, canDM fail-closed, age gate
  pre-auth, prayer purge, parental consent, Berean age gate, deletion cascade).
- Launch-readiness criticals fixed (Aegis review, email-verify gate, AccountStatusGate,
  deep-link guard, ≤3-tap delete, Berean injection guard).
- Info.plist: 4 usage strings present; ITSAppUsesNonExemptEncryption=false; ATT consistent.
- C-8 + C-13 closed this session.
