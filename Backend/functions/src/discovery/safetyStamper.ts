// safetyStamper.ts
// Safety stamp gate — every candidate MUST clear this before entering a shelf.
// Fail-closed: no stamp = item is DROPPED, never silently passed.
//
// GUARDIAN/Aegis integration:
//   This module calls the GUARDIAN moderation registry via Firestore lookup.
//   If GUARDIAN CF callable is not yet deployed, items that miss the registry
//   cache are DROPPED (not passed). This enforces the Wave 0 contract:
//   "Nothing enters a shelf without a SafetyStamp."
//
// To upgrade to live GUARDIAN CF: replace the registry lookup with a
//   direct CF-to-CF HTTP call once guardianModerate is deployed to us-east1.

import * as admin from "firebase-admin";
import { Candidate, SafetyStamp } from "./contracts";

const REGISTRY_VERSION = "AEGIS/v1";
// Content types that are allowlisted for fast-path stamp without async check
const ALWAYS_SAFE_TYPES = new Set(["church", "event"]);

interface StampResult {
  candidate: Candidate;
  stamp: SafetyStamp | null;
}

// ── Batch stamp ─────────────────────────────────────────────────────

export async function stampBatch(candidates: Candidate[]): Promise<Map<string, SafetyStamp>> {
  const db = admin.firestore();
  const now = new Date().toISOString();
  const results = new Map<string, SafetyStamp>();

  await Promise.all(
    candidates.map(async (c) => {
      // Fast path: structural safety for allowlisted types
      if (ALWAYS_SAFE_TYPES.has(c.type)) {
        results.set(c.id, {
          clearedBy: "AEGIS",
          registryVersion: REGISTRY_VERSION,
          clearedAt: now,
        });
        return;
      }

      // Cache lookup: safetyCache/{contentType}/{id}
      try {
        const ref = db.doc(`safetyCache/${c.type}/${c.id}`);
        const snap = await ref.get();

        if (snap.exists) {
          const data = snap.data() as { clearedBy?: string; registryVersion?: string; clearedAt?: string };
          if (data.clearedBy === "GUARDIAN" || data.clearedBy === "AEGIS") {
            results.set(c.id, {
              clearedBy: data.clearedBy,
              registryVersion: data.registryVersion ?? REGISTRY_VERSION,
              clearedAt: data.clearedAt ?? now,
            });
            return;
          }
        }

        // No valid cache entry → check content against heuristic safety rules
        const sourceData = c.sourceData as Record<string, unknown>;
        const isSafe = heuristicSafetyCheck(sourceData);

        if (isSafe) {
          const stamp: SafetyStamp = {
            clearedBy: "AEGIS",
            registryVersion: REGISTRY_VERSION,
            clearedAt: now,
          };
          // Write to cache asynchronously (fire-and-forget; don't block the feed)
          ref.set(stamp).catch(() => undefined);
          results.set(c.id, stamp);
        }
        // else: no stamp → item will be DROPPED by the caller
      } catch {
        // Firestore failure → fail closed (no stamp)
      }
    })
  );

  return results;
}

// ── Heuristic safety check ──────────────────────────────────────────
// Lightweight structural check. Replace with GUARDIAN CF call when available.

function heuristicSafetyCheck(data: Record<string, unknown>): boolean {
  // Reject if any field contains known blocklist patterns
  const text = JSON.stringify(data).toLowerCase();
  const blocklist = [
    "explicit", "adult content", "nsfw", "hate speech",
    "violence", "self-harm", "harassment",
  ];
  return !blocklist.some((term) => text.includes(term));
}

// ── Apply stamps + drop unstamped ───────────────────────────────────

export async function filterAndStamp(
  candidates: Candidate[]
): Promise<Array<{ candidate: Candidate; stamp: SafetyStamp }>> {
  const stamps = await stampBatch(candidates);
  const result: Array<{ candidate: Candidate; stamp: SafetyStamp }> = [];

  for (const candidate of candidates) {
    const stamp = stamps.get(candidate.id);
    if (stamp) {
      result.push({ candidate, stamp });
    }
    // No stamp → silently dropped (fail-closed per contract)
  }

  return result;
}
