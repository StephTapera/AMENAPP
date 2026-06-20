# Moment Verification Ledger

Generated after Wave 1/Wave 2 implementation pass. This ledger blocks flag flips until every FAIL is resolved and human canonical build/deploy steps are complete.

## PASS

- Contracts committed: `7bdfae5f`, `13c95ca9`.
- Flags default off in TS contract: `Contracts/moment/momentContracts.ts:24`.
- Swift mirror default off: `Sources/Contracts/Moment/MomentContracts.swift:53`.
- Deepen endpoints use `us-east1`: `functions/src/moment/deepen/shared.ts:4`.
- Gather stubs use `us-east1`: `functions/src/moment/gather/shared.ts:4`.
- Gather requires `gather_live_enabled` and `gather_compliance_gate_cleared`: `functions/src/moment/gather/shared.ts:25`.
- Gather returns `complianceGateRequired` before compliance clearance: `functions/src/moment/gather/shared.ts:76`.
- Deepen routes through Berean adapter boundary: `functions/src/moment/deepen/shared.ts:197`.
- Berean adapter runs Constitutional Intelligence before GUARDIAN/Aegis: `functions/src/berean/momentAdapter/runMomentDeepen.ts:49`.
- GUARDIAN/Aegis blocks before result return: `functions/src/berean/momentAdapter/runMomentDeepen.ts:61`.
- Living Memory/Pinecone is a typed dependency boundary, not an invented secret: `functions/src/berean/momentAdapter/types.ts:87`.
- Firestore save rules are Deepen-only: `firestore.rules:504`.
- Firestore saved output requires GUARDIAN passed: `firestore.rules:526`.
- Moment documents are owner-read and server-owned for mutation: `firestore.rules:3574`.
- CalmCap no urgency/live-count/reward/streak constraint is represented in the HTML demo: `demos/moment/moment-render-deepen-demo.html:130`.
- SwiftUI Gather control is disabled/gated: `Sources/Features/Moment/MomentSurfaceView.swift:88`.

## FAIL / BLOCKED

- Canonical Xcode build not run by human.
- Firebase deploys not run by human.
- Firestore rules deploy not run by human.
- Credential rotation remains blocked: Anthropic key, Google OAuth2 refresh token, and Algolia key must be rotated before production readiness.
- `firestore.rules` has unrelated in-flight edits from other active work; isolate Moment hunks before committing/deploying.

## Human-Only Commands

```sh
firebase deploy --only functions:momentSummarize --project amen-5e359
firebase deploy --only functions:momentCrossReference --project amen-5e359
firebase deploy --only functions:momentGeneratePrayer --project amen-5e359
firebase deploy --only functions:momentGenerateStudyGuide --project amen-5e359
firebase deploy --only functions:momentGenerateDiscussion --project amen-5e359
firebase deploy --only functions:momentGenerateDevotional --project amen-5e359
firebase deploy --only functions:momentSaveTo --project amen-5e359
firebase deploy --only functions:momentPrayLive --project amen-5e359
firebase deploy --only functions:momentJoinAudio --project amen-5e359
firebase deploy --only functions:momentJoinDiscussion --project amen-5e359
firebase deploy --only firestore:rules --project amen-5e359
```
