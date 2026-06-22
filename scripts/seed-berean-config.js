#!/usr/bin/env node
/**
 * seed-berean-config.js
 *
 * Seeds the Firestore config/credits and config/voice documents required
 * by Berean v1. Run once before enabling the berean callables in production.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json node scripts/seed-berean-config.js
 *
 * Or with the Firebase emulator:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed-berean-config.js
 *
 * Safe to run multiple times — uses merge: true (idempotent).
 */

"use strict";

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "amen-5e359" });
}

const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// config/credits
// ─────────────────────────────────────────────────────────────────────────────
// costByDomain: credits consumed per message for each domain.
// Lower cost = lighter task (proactive, bible lookup).
// Higher cost = grounded RAG + citations (scripture, theology).
// safety and crisis: 0 — NEVER counted against the user.
// capByPlan: weekly credit caps per plan tier.

const creditConfig = {
  costByDomain: {
    scripture:    4,
    prayer:       2,
    devotional:   2,
    theology:     4,
    pastoral:     3,
    study:        3,
    church_notes: 2,
    reflection:   2,
    discovery:    1,
    admin:        1,
    giving:       1,
    general:      1,
    safety:       0,   // NEVER counted — safety always free
    crisis:       0,   // NEVER counted — safety always free
  },
  capByPlan: {
    free: 40,
    plus: 200,
    pro:  1000,
  },
  safetyExemptDomains: ["safety", "crisis"],
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};

// ─────────────────────────────────────────────────────────────────────────────
// config/voice
// ─────────────────────────────────────────────────────────────────────────────

const voiceConfig = {
  personas: [
    { id: "still", label: "Still",  description: "Quiet and unhurried." },
    { id: "warm",  label: "Warm",   description: "Pastoral and present." },
    { id: "clear", label: "Clear",  description: "Crisp and articulate." },
    { id: "plain", label: "Plain",  description: "Simple and direct." },
  ],
  speeds: [
    { id: "slow",   label: "Slow",   rate: 0.8 },
    { id: "normal", label: "Normal", rate: 1.0 },
    { id: "fast",   label: "Fast",   rate: 1.25 },
  ],
  languages: [
    { code: "en-US", label: "English",            beta: false },
    { code: "es-US", label: "Spanish (Beta)",      beta: true  },
    { code: "fr-FR", label: "French (Beta)",       beta: true  },
    { code: "pt-BR", label: "Portuguese (Beta)",   beta: true  },
    { code: "de-DE", label: "German (Beta)",       beta: true  },
    { code: "ko-KR", label: "Korean (Beta)",       beta: true  },
    { code: "zh-CN", label: "Chinese – Simplified (Beta)", beta: true },
    { code: "sw-KE", label: "Swahili (Beta)",      beta: true  },
  ],
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};

async function seed() {
  console.log("Seeding Berean v1 config documents...\n");

  await db.doc("config/credits").set(creditConfig, { merge: true });
  console.log("✅  config/credits seeded");
  console.log("    - safety/crisis domains: 0 credits (always free)");
  console.log("    - free cap: 40 credits/week");
  console.log("    - plus cap: 200 credits/week");
  console.log("    - pro cap: 1000 credits/week");

  await db.doc("config/voice").set(voiceConfig, { merge: true });
  console.log("✅  config/voice seeded");
  console.log("    - 4 personas: still, warm, clear, plain");
  console.log("    - 3 speeds: slow, normal, fast");
  console.log("    - 8 languages (1 stable, 7 beta)");

  console.log("\nSeed complete. These documents are readable by all authenticated users (Firestore rules B-8).");
  console.log("They are writable only by Admin SDK (Cloud Functions).\n");

  process.exit(0);
}

seed().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
