# DEPLOYMENT_TODO.md — Berean Trust Architecture + Safety Hardening

## Session: 2026-06-12 (updated)

> Items 1–17 are carried forward from the previous session. Items 18–35 are new items from
> this build session (safety hardening wave, berean pipeline hardening, COPPA SSO fix,
> DM video moderation, quality audit P0s). Check off items as they are completed.

---

## Section A — Secrets (must be set before any CF deploy)

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 1 | ANTHROPIC_API_KEY | Secret | `firebase functions:secrets:set ANTHROPIC_API_KEY` | Terminal (project root) | Yes | Pending |
| 2 | GEMINI_API_KEY | Secret | `firebase functions:secrets:set GEMINI_API_KEY` | Terminal (project root) | Yes | Pending |
| 3 | BIBLE_API_KEY | Secret | `firebase functions:secrets:set BIBLE_API_KEY` | Terminal (project root) | Yes | Pending |
| 4 | OPENAI_API_KEY | Secret | `firebase functions:secrets:set OPENAI_API_KEY` | Terminal (project root) | Conditional | Pending |

> Verify secrets: `firebase functions:secrets:access ANTHROPIC_API_KEY` (returns value if set)

**Note on item 4:** `openai` npm package is not in `functions/package.json` as of this session. If any new CF requires it, first run `cd functions && npm install openai` before deploying. Confirm need before adding.

---

## Section B — TypeScript Compile

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 5 | Compile berean TypeScript | Build | `cd "functions/berean" && npx tsc --project tsconfig.json` | Terminal | Yes | Pending |

> Verify: `ls "functions/berean/lib/" \| head -10` — lib/ directory should contain compiled .js files

---

## Section C — Cloud Function Deploys

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 6 | Deploy bereanPipeline | Deploy | `firebase deploy --only functions:bereanConstitutionalPipeline` | Terminal | Yes | Pending |
| 7 | Deploy constitutionalReview | Deploy | `firebase deploy --only functions:constitutionalReview` | Terminal | Yes | Pending |
| 8 | Deploy modelRouter | Deploy | `firebase deploy --only functions:modelRouter` | Terminal | Yes | Pending |
| 9 | Deploy berean memory CFs (all 5) | Deploy | `firebase deploy --only functions:bereanGetMemory,functions:bereanDeleteMemory,functions:bereanToggleMemoryLock,functions:bereanUpdateMemory,functions:bereanDeleteAllMemory` | Terminal | Yes | Pending |
| 10 | Deploy bereanRunEvals | Deploy | `firebase deploy --only functions:bereanRunEvals` | Terminal | Before launch | Pending |
| 11 | Deploy bereanSubmitFeedback | Deploy | `firebase deploy --only functions:bereanSubmitFeedback` | Terminal | Yes | Pending |
| 12 | Deploy verifyScriptureText | Deploy | `firebase deploy --only functions:verifyScriptureText` | Terminal | Before launch | Pending |
| 13 | Deploy ALL berean CFs in one command | Deploy | `firebase deploy --only functions:bereanConstitutionalPipeline,functions:bereanGetMemory,functions:bereanDeleteMemory,functions:bereanToggleMemoryLock,functions:bereanUpdateMemory,functions:bereanDeleteAllMemory,functions:bereanSubmitFeedback,functions:bereanRunEvals,functions:verifyScriptureText` | Terminal | Yes | Pending |

> Verify after each deploy: `firebase functions:list \| grep berean` — all functions should show status ACTIVE with region us-east1

---

## Section D — Firestore Rules + Indexes

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 14 | Deploy Firestore rules | Deploy | `firebase deploy --only firestore:rules` | Terminal | Yes | Pending |
| 15 | Deploy Firestore indexes | Deploy | `firebase deploy --only firestore:indexes` | Terminal | Before launch | Pending |

> Verify rules: Firebase Console → Firestore → Rules → confirm `bereanTrustArchitecture` block is present and last published timestamp is today

---

## Section E — Remote Config Feature Flags

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 16 | Set constitutionalIntelligence_enabled | Config | Firebase Console → Remote Config → Add parameter `constitutionalIntelligence_enabled` = `false` (String). Publish. | Firebase Console | Yes | Pending |
| 17 | Set berean_memory_enabled | Config | Firebase Console → Remote Config → Add parameter `berean_memory_enabled` = `false` (String). Publish. | Firebase Console | Yes | Pending |
| 18 | Set berean_feedback_enabled | Config | Firebase Console → Remote Config → Add parameter `berean_feedback_enabled` = `true` (String). Publish. | Firebase Console | Yes | Pending |
| 19 | Set all Trust Architecture flags (bulk) | Config | Firebase Console → Remote Config → Add all: `trustArchitecture_modelRouter=false`, `trustArchitecture_evidenceRetrieval=false`, `trustArchitecture_constitutionalPipeline=false`, `trustArchitecture_memoryLayer=false`, `trustArchitecture_feedbackCapture=false`. Publish. | Firebase Console | Before launch | Pending |

> Verify: Firebase Console → Remote Config → confirm all flags show correct default values and publish timestamp

---

## Section F — Firestore Seeding + Configuration

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 20 | Seed berean_constitution/v1 | Config | `node -e "const admin=require('firebase-admin'); admin.initializeApp(); const data=require('./functions/berean-constitution-v1.json'); admin.firestore().doc('berean_constitution/v1').set(data).then(()=>{ console.log('seeded'); process.exit(0); })"` — run from project root after `export GOOGLE_APPLICATION_CREDENTIALS=<path-to-service-account.json>` | Terminal | Yes | Pending |
| 21 | Create featureFlags/trustArchitecture doc | Config | Firebase Console → Firestore → Collection `featureFlags` → Document `trustArchitecture` → Add fields: `modelRouter=false`, `evidenceRetrieval=false`, `constitutionalPipeline=false`, `memoryLayer=false`, `feedbackCapture=false` | Firebase Console | Yes | Pending |
| 22 | Seed bereanTheologyCorpus | Config | Firebase Console → Firestore → Collection `bereanTheologyCorpus` → Add 5–10 documents with fields: `title` (string), `content` (string), `source` (string), `denomination` (string) | Firebase Console | Before launch | Pending |

> Verify Firestore seed: Firebase Console → Firestore → `berean_constitution/v1` → confirm document has expected fields from berean-constitution-v1.json

---

## Section G — iOS App / Xcode Steps

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 23 | Add new Berean Swift files to AMENAPP target | Xcode | Xcode → Project Navigator → select each of: `BereanTrustBadge.swift`, `BereanEvidenceSheet.swift`, `BereanConstitutionalPipeline.swift`, `BereanMemoryView.swift`, `BereanFeedbackRating.swift` → File Inspector → Target Membership → check AMENAPP | Xcode | Yes | Pending |
| 24 | Update PrivacyInfo.xcprivacy | Xcode | Open `AMENAPP/PrivacyInfo.xcprivacy` in Xcode. Add data type `NSPrivacyCollectedDataTypeOtherAppUsageData` (Berean response ratings/feedback). Add `NSPrivacyAccessedAPITypeReasons` entries for: `berean_pipeline_traces` (linked to AI interaction improvement), `berean_feedback` (user-initiated feedback), `berean_memory` (AI personalization with user consent). | Xcode → AMENAPP/PrivacyInfo.xcprivacy | Before submission | Pending |
| 25 | Verify App Check enforcement on new callables | Xcode/Firebase | Firebase Console → App Check → confirm all `berean*` callables show enforcement status "Enforced" (not "Monitoring"). Device test: call bereanConstitutionalPipeline without App Check token — expect `app-check-token-is-invalid` error. | Firebase Console + device | Yes | Pending |
| 26 | Verify no secrets in iOS client bundle | Xcode | Run: `grep -r "ANTHROPIC\|sk-ant\|sk-\|AIza" "AMENAPP/" --include="*.swift" --include="*.plist" --include="*.xcconfig"` — must return no matches. | Terminal | Yes — blocks submission | Pending |
| 27 | Verify Reduce Motion compliance | Xcode/Device | On device: Settings → Accessibility → Motion → Reduce Motion ON → launch app → confirm no auto-playing animations persist. Key surfaces: feed scroll, Berean response cards, post transitions. | Device | Before submission | Pending |
| 28 | Verify offline graceful degradation | Device | Airplane Mode → open app → tap Berean → confirm error state shows user-friendly message, does not crash, does not show blank white screen. | Device | Before submission | Pending |

---

## Section H — Privacy + Legal

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 29 | Update Privacy Policy — AI feedback disclosure | Manual | Add section to Privacy Policy: "AI Interaction Data: When you use Berean AI features, we may collect: (1) your queries and AI responses (pipeline traces), (2) feedback ratings (thumbs up/down) and optional comments, (3) AI-inferred preferences and study topics (Berean Memory). Pipeline traces are retained for 90 days. Memory data is retained until you delete it or your account. You may view, edit, lock, and delete all memory entries at any time in Settings → Berean → Memory." | Website CMS + App Store Connect Privacy Policy URL | Before submission | Pending |
| 30 | Verify account deletion cascade covers AI data | Code review | Confirm `functions/accountDeletion.js` (or `processAccountDeletion`) calls `deleteAllUserMemory(uid, db)` and batch-deletes `bereanPipelineTraces` (userId==uid), `bereanFeedback` (userId==uid), `bereanModelLogs` (userId==uid). This is P0-05 from the 2026-06-12 quality audit. | Code + Firebase Console | Yes — GDPR/blocks submission | Pending |

---

## Section I — App Store Checklist (final gate)

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 31 | Verify AI content is labeled | Review | Confirm all Berean AI responses display disclosure label (e.g. "Powered by Berean AI"). Check BereanResponseView / BereanTrustBadge surfaces. | Code review + device | Before submission | Pending |
| 32 | Verify Blaze plan is active | Billing | Firebase Console → Usage & Billing → confirm project is on Blaze (pay-as-you-go) plan. Required for Cloud Functions v2 and external API calls (Anthropic, Google AI). | Firebase Console | Yes | Pending |
| 33 | Run eval baseline after deploy | Test | After CFs are deployed: call `bereanRunEvals` callable from an admin account. Verify pass rates: Bible ≥ 90%, Safety ≥ 95%, Product ≥ 80%, Technical ≥ 75%, Moderation ≥ 90%. Gate result must be `canDeploy: true`. | Firebase Console → Functions → Shell, or test device with admin account | Before launch | Pending |
| 34 | Confirm aps-environment = production | Xcode | Xcode → AMENAPP target → Signing & Capabilities → Push Notifications → confirm `aps-environment` entitlement is `production` (not `development`) before final archive. | Xcode | Before submission | Pending |
| 35 | COPPA age-gate SSO paths | Verify | Verify P0-09 fix (commit 28b849e2) is active: onboarding SSO paths (Sign in with Apple, Google) must block users who have not provided DOB confirming age ≥ 13. Test: create account via SSO, skip DOB → should be blocked at onboarding gate, not reach feed. | Device | Yes — blocks submission | Pending |

---

## Section J — Safety-Hardening Wave 2 Deploys

| # | Item | Type | Action Required (exact command) | Where | Blocking? | Status |
|---|------|------|---------------------------------|-------|-----------|--------|
| 36 | Deploy moderateUploadedDMVideo CF | Deploy | `firebase deploy --only functions:moderateUploadedDMVideo` | Terminal | Yes | Pending |
| 37 | Verify DM video moderation active | Verify | Firebase Console → Functions → `moderateUploadedDMVideo` → confirm status ACTIVE. Test: upload video to DM from test account → confirm moderation event logged in `mediaModerationPipeline` Firestore collection. | Firebase Console + device | Yes | Pending |
| 38 | Verify berean pipeline hardening (P0-06 fix) | Verify | Confirm `functions/berean/constitutionalPipeline.ts` catch block returns safe error output (NOT `legacyPipelineCall`). Run: `grep -n "legacyPipelineCall" "Backend/functions/src/berean/constitutionalPipeline.ts"` — the catch block line must NOT call legacyPipelineCall. | Terminal | Yes — safety critical | Pending |

---

## Section K — Verification Commands Quick Reference

Run these after completing the deploy sections above:

```bash
# Confirm all berean CFs are live
firebase functions:list | grep berean

# Confirm no secrets leak in iOS source
grep -r "ANTHROPIC\|sk-ant\|AIza" "AMENAPP/" --include="*.swift" --include="*.plist" 2>/dev/null

# Confirm constitutional pipeline catch block is safe
grep -n "legacyPipelineCall" "Backend/functions/src/berean/constitutionalPipeline.ts"

# Confirm account deletion cascade includes AI data collections
grep -n "bereanMemory\|bereanPipelineTraces\|bereanFeedback" "functions/accountDeletion.js"

# Confirm secrets are set
firebase functions:secrets:access ANTHROPIC_API_KEY
firebase functions:secrets:access GEMINI_API_KEY
firebase functions:secrets:access BIBLE_API_KEY
```

---

## Completion Checklist

- [ ] Section A (Secrets) — all 3 required secrets set
- [ ] Section B (Build) — TypeScript compiles clean
- [ ] Section C (CFs) — all berean CFs ACTIVE in us-east1
- [ ] Section D (Firestore) — rules and indexes deployed
- [ ] Section E (Remote Config) — all flags published with correct defaults
- [ ] Section F (Firestore seed) — constitution seeded, featureFlags doc created
- [ ] Section G (iOS) — target membership, PrivacyInfo, App Check verified
- [ ] Section H (Privacy) — Privacy Policy updated, account deletion cascade confirmed
- [ ] Section I (App Store) — AI labeling, Blaze plan, eval baseline pass, aps-environment
- [ ] Section J (Safety) — DM video moderation live, pipeline hardening verified
- [ ] Section K (Verification) — all quick-reference checks pass

---

*Last updated: 2026-06-12 | Branch: safety-hardening | Session: berean pipeline hardening + COPPA SSO fix + DM video moderation*
