// bereanContextFetcher.ts — Backend/functions/src/intelligence
// Callable: fetchBereanContext
// Retrieves recent context signals for a user to power BereanContextRAGService on the client.
//
// Invariants:
//  • Only returns signals with tierCeiling != "s" (Tier-S is device-only)
//  • Max 10 signals per response; sorted oldest-first
//  • Requires the caller's Firebase Auth UID — cannot query another user's signals
//  • Deployed to us-east1 (us-central1 quota exhausted as of 2026-06-13)

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const FORMATION_SIGNAL_TYPES = new Set([
  "noteSaved",
  "noteThemeDetected",
  "prayerCreated",
  "prayerAnswered",
  "studyStarted",
  "studyCompleted",
  "verseReflected",
  "visitVerified",
]);

interface BereanSignalSummary {
  signalType: string;
  subjectNodeType: string;
  subjectNodeID: string;
  occurredAt: string;   // ISO 8601
  payloadSnippet: string;
}

export const fetchBereanContext = functions.onCall(
  { region: "us-east1" },
  async (request): Promise<{ signals: BereanSignalSummary[]; provenanceLabel: string }> => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Auth required");
    }

    const uid = request.auth.uid;
    const requestedUID = request.data?.uid as string | undefined;

    // Only allow fetching your own context
    if (requestedUID && requestedUID !== uid) {
      throw new functions.HttpsError("permission-denied", "Cannot fetch another user's context");
    }

    const db = admin.firestore();
    const snap = await db
      .collection("contextSignals")
      .doc(uid)
      .collection("signals")
      .where("tierCeiling", "!=", "s")
      .orderBy("tierCeiling")                    // required by Firestore for != filter
      .orderBy("occurredAt", "desc")
      .limit(20)
      .get();

    const signals: BereanSignalSummary[] = snap.docs
      .filter((doc) => FORMATION_SIGNAL_TYPES.has(doc.data().type))
      .slice(0, 10)
      .reverse()   // oldest-first
      .map((doc) => {
        const d = doc.data();
        const refs: Array<{ nodeType: string; nodeID: string }> = d.subjectRefs ?? [];
        const firstRef = refs[0] ?? { nodeType: "unknown", nodeID: "" };
        const payload = d.payload ?? {};
        const snippetRaw = Object.values(payload)[0];
        const snippet = typeof snippetRaw === "string"
          ? snippetRaw.slice(0, 120)
          : JSON.stringify(snippetRaw ?? "").slice(0, 120);

        const occurredAt: FirebaseFirestore.Timestamp = d.occurredAt;

        return {
          signalType: d.type ?? "unknown",
          subjectNodeType: firstRef.nodeType,
          subjectNodeID: firstRef.nodeID,
          occurredAt: occurredAt.toDate().toISOString(),
          payloadSnippet: snippet,
        };
      });

    const typeCounts: Record<string, number> = {};
    for (const s of signals) {
      typeCounts[s.signalType] = (typeCounts[s.signalType] ?? 0) + 1;
    }
    const provenance = Object.entries(typeCounts)
      .map(([k, v]) => `${v} ${k}`)
      .join(", ");

    return {
      signals,
      provenanceLabel: signals.length > 0 ? `from ${provenance}` : "no recent signals",
    };
  }
);
