#!/usr/bin/env node
// initSafetyFlags.js
// One-time Firestore seed for safety system feature flags and config defaults.
//
// Run BEFORE deploying the safety Cloud Functions:
//   cd functions
//   node scripts/initSafetyFlags.js
//
// Prerequisites:
//   - GOOGLE_APPLICATION_CREDENTIALS env var pointing to a service account JSON
//     OR run from a machine authenticated with `gcloud auth application-default login`
//   - `npm install` has been run in the functions/ directory
//   - Set the FIREBASE_PROJECT env var to your Firebase project ID:
//     FIREBASE_PROJECT=my-amen-project node scripts/initSafetyFlags.js

"use strict";

const admin = require("firebase-admin");

const PROJECT = process.env.FIREBASE_PROJECT;
if (!PROJECT) {
  console.error("[initSafetyFlags] ERROR: Set FIREBASE_PROJECT environment variable.");
  console.error("  Example: FIREBASE_PROJECT=my-amen-project node scripts/initSafetyFlags.js");
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

async function run() {
  console.log(`[initSafetyFlags] Seeding safety config for project: ${PROJECT}`);

  // ── 1. Feature flags ──────────────────────────────────────────────────────
  // minorSafetyEnabled: MUST stay false until all policy decisions in
  //   docs/safety/MINOR_SAFETY.md §7 are signed off by Legal + Product.
  // abuseDetectionEnabled: true — signals are metadata-only (no enforcement),
  //   safe to enable immediately after deploy.
  // appealsEnabled: true — appeals UI can be exposed to users once deployed.
  await db.doc("config/featureFlags").set(
    {
      minorSafetyEnabled: false,       // [DECISION REQUIRED] — activate only after MINOR_SAFETY.md §9 checklist complete
      abuseDetectionEnabled: true,     // metadata-only signals; safe default ON
      appealsEnabled: true,            // appeals flow is ready; enable after deploy
      crisisResourcesFromFirestore: false, // if true, checkForCrisis reads config/crisisResources instead of hardcoded list
    },
    { merge: true }
  );
  console.log("  ✓ config/featureFlags");

  // ── 2. AI rate limits ─────────────────────────────────────────────────────
  // openaiDailyOrgCap: global daily call ceiling across all users.
  // Tune these in the Firebase console once you have baseline usage data.
  await db.doc("config/aiLimits").set(
    {
      openaiDailyOrgCap: 10000,   // calls/day, all users combined (openAIProxy)
      anthropicDailyOrgCap: 5000, // calls/day, all users combined (Berean + AI features)
    },
    { merge: true }
  );
  console.log("  ✓ config/aiLimits");

  // ── 3. Crisis resources (Firestore hot-update path) ───────────────────────
  // [DECISION REQUIRED]: crisisDetectionHook.js reads this collection ONLY if
  //   config/featureFlags.crisisResourcesFromFirestore === true.
  //   Currently hardcoded in the function; flip the flag + populate here when
  //   regional resource list is finalised (see CRISIS_RESPONSE.md §5).
  await db.doc("config/crisisResources").set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      resources: [
        { name: "988 Suicide & Crisis Lifeline", contact: "Call or text 988", region: "US" },
        { name: "Crisis Text Line", contact: "Text HOME to 741741", region: "US" },
        {
          name: "International Association for Suicide Prevention",
          contact: "https://www.iasp.info/resources/Crisis_Centres/",
          region: "international",
        },
        // [DECISION REQUIRED]: add regional resources before flipping crisisResourcesFromFirestore
        // { name: "Samaritans", contact: "116 123", region: "UK" },
        // { name: "Talk Suicide Canada", contact: "1-833-456-4566", region: "CA" },
        // { name: "Lifeline Australia", contact: "13 11 14", region: "AU" },
      ],
    },
    { merge: true }
  );
  console.log("  ✓ config/crisisResources (populated; flag off — hardcoded list still active)");

  // ── 4. Abuse detection thresholds ────────────────────────────────────────
  // [DECISION REQUIRED]: MINOR_SAFETY.md and ABUSE_DETECTION.md both flag
  //   these as needing Trust & Safety sign-off. Current values match the
  //   placeholder constants in abuseDetectionSignals.js.
  await db.doc("config/abuseDetection").set(
    {
      massDmThresholdPerHour: 20,       // [DECISION REQUIRED] — see ABUSE_DETECTION.md D-08
      moneyMentionThresholdPerDay: 5,   // [DECISION REQUIRED] — see ABUSE_DETECTION.md D-03
      storeContentSnippetAboveConfidence: null, // null = never store; [DECISION REQUIRED] D-11
    },
    { merge: true }
  );
  console.log("  ✓ config/abuseDetection");

  // ── 5. Ensure meta/anonymousBereanUsage exists (avoids first-write race) ─
  const anonRef = db.doc("meta/anonymousBereanUsage");
  const anonSnap = await anonRef.get();
  if (!anonSnap.exists) {
    await anonRef.set({ dailyKey: "", todayCalls: 0 });
    console.log("  ✓ meta/anonymousBereanUsage (initialised)");
  } else {
    console.log("  – meta/anonymousBereanUsage (already exists, skipped)");
  }

  console.log("\n[initSafetyFlags] Done. Review any [DECISION REQUIRED] comments before production.");
  process.exit(0);
}

run().catch((err) => {
  console.error("[initSafetyFlags] FATAL:", err);
  process.exit(1);
});
