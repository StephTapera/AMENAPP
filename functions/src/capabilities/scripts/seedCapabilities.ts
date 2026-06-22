// scripts/seedCapabilities.ts — Idempotent capability registry seed (Wave 1: Lane B)
//
// Seeds three v1 capabilities to `capabilities/{id}`.
// Safe to re-run: checks for existing docs before writing.
//
// Run via: npx ts-node -P functions/tsconfig.capabilities.json \
//            functions/src/capabilities/scripts/seedCapabilities.ts

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { CapabilityManifest } from "../types";

// Initialize Firebase Admin (uses ADC / GOOGLE_APPLICATION_CREDENTIALS)
initializeApp();

const CAPABILITIES: CapabilityManifest[] = [
  {
    id: "prayer_os",
    displayName: "Prayer OS",
    tagline: "Track prayers, follow up with care",
    iconSymbol: "hands.and.sparkles",
    surfaces: ["berean", "messages"],
    requiredContext: ["prayerHistory"],
    optionalContext: ["messagesMeta"],
    entryFunction: "prayerOS_createCard",
    minAppVersion: "1.0.0",
    status: "active",
    tier: "free",
  },
  {
    id: "scripture_intelligence",
    displayName: "Scripture Intelligence",
    tagline: "Auto-detect and explore Bible references",
    iconSymbol: "book.and.wand",
    surfaces: ["notes"],
    requiredContext: ["notesContent"],
    optionalContext: ["readingHistory"],
    entryFunction: "scripture_detectReferences",
    minAppVersion: "1.0.0",
    status: "active",
    tier: "free",
  },
  {
    id: "verse_lookup",
    displayName: "Verse Lookup",
    tagline: "Find and insert Bible verses anywhere",
    iconSymbol: "text.book.closed",
    surfaces: ["berean", "messages", "notes"],
    requiredContext: [],
    optionalContext: ["readingHistory"],
    entryFunction: "scripture_getVerses",
    minAppVersion: "1.0.0",
    status: "active",
    tier: "free",
  },
];

async function seed(): Promise<void> {
  const db = getFirestore();

  console.log(`Seeding ${CAPABILITIES.length} capabilities...`);

  for (const cap of CAPABILITIES) {
    const ref = db.collection("capabilities").doc(cap.id);
    const snap = await ref.get();

    if (snap.exists) {
      console.log(`  already exists: ${cap.id}`);
      continue;
    }

    await ref.set(cap);
    console.log(`  seeded: ${cap.id}`);
  }

  console.log("Done.");
}

seed().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
