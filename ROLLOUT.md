# SELAH Rollout Plan

## Principle
Each flag is an independent kill switch. Flag OFF = zero UI + zero network. Proven in V1 flag-off invisibility tests.

## Recommended Rollout Sequence

### Phase 1 — Foundation (lowest risk, infrastructure only)
Enable: breathMotion, selahMoments, liturgicalTheming
Risk: Low — visual only, no data writes, no network calls beyond existing surfaces
Rollback: flag OFF = instant revert

### Phase 2 — Transparency (high-value, low blast radius)
Enable: feedWhyAmISeeingThis
Risk: Low-medium — new Firestore reads + 1 new CF (generateFeedExplanation)
Rollback: flag OFF

### Phase 3 — Connection (new Firestore collections)
Enable: commitmentConnections, tables, prayerChains
Risk: Medium — new collections, scheduled CFs (closeTheLoopNudge, sunsetTable)
Rollback: flag OFF (existing data preserved, just not displayed)
Pre-condition: Firestore rules for commitments/, tables/, prayerChains/ deployed

### Phase 4 — Berean Intelligence (AI features)
Enable: bereanPersonalContext, bereanTraditionAware, bereanNotebooksGroups, bereanRoomFirst
Risk: Medium — new CF calls, modified Berean system prompt (addendum only)
Rollback: flag OFF
Pre-condition: retrievePersonalContext + generateDiscussionGuide CFs deployed

### Phase 5 — Creation (new content types)
Enable: testimonies, remixLineage, bereanCoCreator
Risk: Medium — new Firestore collections, C2PA manifest generation CF
Rollback: flag OFF (existing published testimonies preserved)
Pre-condition: generateC2PAManifest + createRemixLineage CFs deployed

### Phase 6 — Safety (last, most scrutinized)
Enable: aegisC59, youthMode
Risk: Low-medium — safety features; false positive risk managed by 0.7 confidence threshold
Rollback: flag OFF
Pre-condition: Human review of AegisC59 pattern list + youth account age-signal verification

## Firestore Rules Required (before Phase 3)
- commitments/{id}: read/write for parties[] members only
- tables/{id}: read for members, write via Cloud Function (joinTable) only
- prayerChains/{id}: read for requestRef author + chain members only
- feedExplanations/{id}: read for authenticated uid only
- remixLineage/{id}: read for all, write via CF only

## Deploy Checklist
- [ ] All 11 selah*.ts functions deployed to us-central1
- [ ] Firestore rules updated and emulator-tested
- [ ] Remote Config keys created: selah_breath_motion, selah_moments, etc. (all default false)
- [ ] Phase 1 flags enabled in Remote Config
- [ ] Monitor cold start timings post-deploy (target < 3s)

## Open Items Before Any Flag Flip
- HIGH: Space invite flow missing youth-shield check (see AUDIT.md — requires human-reviewed CF change to AmenCreateSpaceViewModel + createSpace CF)
- INFO: BereanCoCreatorService prompt injection latent risk — must be addressed when backend call is wired in (see AUDIT.md)

## Rollback Procedures
All phases: set the corresponding Remote Config flag(s) to false. Change propagates within 60 seconds. No data migration required; all new collections are additive and will simply not be read when flags are off. Scheduled CFs (closeTheLoopNudge, sunsetTable) can be paused via Cloud Scheduler without iOS deployment.
