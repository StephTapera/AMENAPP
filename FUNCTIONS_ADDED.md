# SELAH Build — Cloud Functions Added

## New Functions (all region: us-central1)

### selahConnection.ts
- joinTable: transaction-based Table join with cap enforcement
- closeTheLoopNudge: scheduled every 6 hours — commitment close-the-loop notifications
- sunsetTable: scheduled every 24 hours — archives expired Tables
- assemblePrayerChain: assembles chain links into woven artifact

### selahCreation.ts
- generateC2PAManifest: provenance manifest generation for testimonies
- createRemixLineage: transactional remix attribution chain write

### selahBerean.ts
- generateDiscussionGuide: AI-generated pre-meeting guide for Table notebooks
- retrievePersonalContext: personal context retrieval (tier-filtered, never Tier P)

### selahSafety.ts
- generateFeedExplanation: warm plain-language feed explanations
- enforceYouthDMPolicy: youth DM enforcement + Aegis C59 detection
- detectAegisC59: spiritual abuse pattern detection (Tier S/C only)

## Total: 11 new functions
## Cold Start Budget: all functions target < 3s cold start (standard onCall timeout is 60s)
## Migration: all schema changes are additive fields only — no existing collections modified
