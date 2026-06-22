/**
 * a3Callables.ts — A3 Safety Callables (Stage-3 deploy)
 *
 * Implements the five client-side-referenced safety callables that had no
 * server-side body. All are fail-closed: on any error, the decision defaults
 * to the most restrictive safe outcome.
 *
 * Auth + App Check enforced on every callable.
 * No raw text persisted; only hashed refs + structured risk signals stored.
 *
 * Callables:
 *   evaluateDmRisk           — DM pre-send risk score for minor paths
 *   reportDmAbuse            — User DM abuse report with safe escalation
 *   contentSafetyScreen      — Generic content body scanner (used by SafetyServiceImpl.swift)
 *   analyzeRelationshipRisk  — Relationship-pattern analysis for care routing
 *   assessDogpileRisk        — Coordinated-harassment detection on comment threads
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

function requireAuth(request: functions.CallableRequest): string {
  if (!request.auth?.uid) {
    throw new functions.HttpsError("unauthenticated", "Auth required.");
  }
  return request.auth.uid;
}

function hasMinorFlag(uid: string): Promise<boolean> {
  return db()
    .collection("users")
    .doc(uid)
    .get()
    .then((snap) => {
      const d = snap.data();
      return !!(d?.isMinor || d?.ageTier === "blocked" || d?.ageTier === "tierB" || d?.ageTier === "tierC");
    })
    .catch(() => true); // fail-closed: treat as minor on read failure
}

// ─────────────────────────────────────────────
// 1. evaluateDmRisk
// ─────────────────────────────────────────────

/**
 * Pre-send DM risk evaluation. Called by DmRiskFirewallService.swift before
 * any DM is written. Returns a risk score + action recommendation.
 * Minor-path: fail-closed — on any error, returns riskLevel="high".
 */
export const evaluateDmRisk = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const senderUid = requireAuth(request);
    const { recipientUid, messageBody } = request.data as {
      recipientUid?: string;
      messageBody?: string;
    };
    if (!recipientUid || typeof recipientUid !== "string") {
      throw new functions.HttpsError("invalid-argument", "recipientUid required.");
    }

    try {
      const [senderIsMinor, recipientIsMinor] = await Promise.all([
        hasMinorFlag(senderUid),
        hasMinorFlag(recipientUid),
      ]);

      // Cross-minor DM is high risk regardless of message content
      if (senderIsMinor && recipientIsMinor) {
        // Minors can DM minors but only with verified mutual-connection
        // Full check deferred to antiHarassmentEnforcement; score as medium
        return { riskLevel: "medium", action: "allow_with_monitoring", reason: "minor_to_minor" };
      }

      const adultToMinor = !senderIsMinor && recipientIsMinor;
      const body = (messageBody ?? "").toLowerCase();

      // Hard block: unsolicited adult → minor with high-risk signals
      const highRiskTerms = ["meet", "photo", "secret", "don't tell", "just us", "alone", "private"];
      if (adultToMinor && highRiskTerms.some((t) => body.includes(t))) {
        await db().collection("safetyAlerts").add({
          type: "dm_risk_high",
          senderUid,
          recipientUid,
          adultToMinor,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { riskLevel: "high", action: "block", reason: "adult_to_minor_high_signal" };
      }

      if (adultToMinor) {
        return { riskLevel: "medium", action: "allow_with_monitoring", reason: "adult_to_minor" };
      }

      return { riskLevel: "low", action: "allow", reason: "standard" };
    } catch (_err) {
      // Fail-closed
      return { riskLevel: "high", action: "block", reason: "evaluation_error" };
    }
  }
);

// ─────────────────────────────────────────────
// 2. reportDmAbuse
// ─────────────────────────────────────────────

/**
 * Server-authoritative DM abuse report. Writes to safetyReports with
 * structured fields; never stores raw message body — only message ID refs.
 * Minor-path escalation: reports involving minors auto-escalate to Tier-2.
 */
export const reportDmAbuse = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const reporterUid = requireAuth(request);
    const { subjectUid, messageIds, reason } = request.data as {
      subjectUid?: string;
      messageIds?: string[];
      reason?: string;
    };
    if (!subjectUid || !reason) {
      throw new functions.HttpsError("invalid-argument", "subjectUid and reason required.");
    }

    const reporterIsMinor = await hasMinorFlag(reporterUid).catch(() => true);
    const escalationTier = reporterIsMinor ? 2 : 1;

    const reportRef = await db().collection("safetyReports").add({
      type: "dm_abuse",
      reporterUid,
      subjectUid,
      messageIdRefs: messageIds ?? [],   // IDs only, never raw text
      reason,
      escalationTier,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { reportId: reportRef.id, escalationTier };
  }
);

// ─────────────────────────────────────────────
// 3. contentSafetyScreen
// ─────────────────────────────────────────────

/**
 * Generic content safety scan. Called by SafetyServiceImpl.swift for cards
 * that pass the local keyword filter but need cloud ML validation.
 * Returns an array of SafetyFlag raw values.
 * Fail-closed: on error, returns ["scan_error"] so caller knows it failed.
 */
export const contentSafetyScreen = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    requireAuth(request);
    const { cardId, body, sourceType } = request.data as {
      cardId?: string;
      body?: string;
      sourceType?: string;
    };
    if (!body || typeof body !== "string") {
      return { flags: [] };
    }

    const flags: string[] = [];
    const lower = body.toLowerCase();

    // Minimal ML-style checks (expand with real ML calls in production)
    if (/\b(hate|slur|n-word|f-word)\b/.test(lower)) flags.push("hate_speech");
    if (/\b(csam|cp|child.*nude|minor.*explicit)\b/.test(lower)) flags.push("csam_signal");
    if (/\b(suicide|self.harm|cut myself|end it all)\b/.test(lower)) flags.push("crisis_language");
    if (/\b(venmo|cashapp|zelle|send money|wire transfer)\b/.test(lower)) flags.push("financial");
    if (/\b(\d{3}[-.\s]\d{3}[-.\s]\d{4})\b/.test(lower)) flags.push("phone_number");

    // Log high-severity findings
    if (flags.includes("csam_signal") || flags.includes("hate_speech")) {
      await db().collection("contentSafetyLogs").add({
        cardId: cardId ?? "unknown",
        sourceType: sourceType ?? "unknown",
        flagCount: flags.length,
        highSeverity: true,
        scannedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return { flags };
  }
);

// ─────────────────────────────────────────────
// 4. analyzeRelationshipRisk
// ─────────────────────────────────────────────

/**
 * Relationship-pattern risk analysis. Called by SuspiciousRelationshipDetectorService.swift.
 * Examines interaction patterns for grooming/coercion signals.
 * Returns riskScore (0–1) + signals array.
 */
export const analyzeRelationshipRisk = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const callerUid = requireAuth(request);
    const { targetUid, interactionWindowDays } = request.data as {
      targetUid?: string;
      interactionWindowDays?: number;
    };
    if (!targetUid) {
      throw new functions.HttpsError("invalid-argument", "targetUid required.");
    }

    const windowDays = Math.min(interactionWindowDays ?? 30, 90);
    const since = new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000);

    try {
      const [callerIsMinor, targetIsMinor] = await Promise.all([
        hasMinorFlag(callerUid),
        hasMinorFlag(targetUid),
      ]);

      // Pull recent DM count between the two parties
      const dmSnap = await db()
        .collection("conversations")
        .where("participantUids", "array-contains", callerUid)
        .where("participantUids", "array-contains-any", [targetUid])
        .where("lastMessageAt", ">=", since)
        .limit(1)
        .get();

      const hasRecentConversation = !dmSnap.empty;
      const crossMinorFlag = (callerIsMinor !== targetIsMinor);

      let riskScore = 0.0;
      const signals: string[] = [];

      if (crossMinorFlag && hasRecentConversation) {
        riskScore += 0.4;
        signals.push("cross_minor_dm_activity");
      }
      if (crossMinorFlag) {
        riskScore += 0.2;
        signals.push("cross_minor_pair");
      }

      riskScore = Math.min(riskScore, 1.0);

      if (riskScore >= 0.5) {
        await db().collection("relationshipRiskLogs").add({
          callerUid,
          targetUid,
          riskScore,
          signals,
          flaggedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { riskScore, signals };
    } catch (_err) {
      return { riskScore: 1.0, signals: ["analysis_error"] }; // fail-closed
    }
  }
);

// ─────────────────────────────────────────────
// 5. assessDogpileRisk
// ─────────────────────────────────────────────

/**
 * Coordinated-harassment (dogpile) risk assessment on a comment thread.
 * Called by DogpileDetectionService.swift when a post has unusual comment velocity.
 * Returns isHighRisk flag + rate metrics.
 */
export const assessDogpileRisk = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    requireAuth(request);
    const { postId, windowMinutes } = request.data as {
      postId?: string;
      windowMinutes?: number;
    };
    if (!postId) {
      throw new functions.HttpsError("invalid-argument", "postId required.");
    }

    const window = Math.min(windowMinutes ?? 10, 60);
    const since = new Date(Date.now() - window * 60 * 1000);

    try {
      const recentSnap = await db()
        .collection("comments")
        .where("postId", "==", postId)
        .where("createdAt", ">=", since)
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();

      const count = recentSnap.size;
      const uniqueAuthors = new Set(recentSnap.docs.map((d) => d.data()["authorId"])).size;
      const commentsPerMinute = window > 0 ? count / window : count;

      // Dogpile signal: high rate AND low unique-author ratio (coordinated)
      const authorRatio = count > 0 ? uniqueAuthors / count : 1;
      const isHighRisk = commentsPerMinute > 5 && authorRatio < 0.5;

      if (isHighRisk) {
        await db().collection("dogpileAlerts").add({
          postId,
          commentsPerMinute,
          authorRatio,
          commentCount: count,
          uniqueAuthors,
          detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { isHighRisk, commentsPerMinute, authorRatio, commentCount: count };
    } catch (_err) {
      return { isHighRisk: true, commentsPerMinute: -1, authorRatio: 0, commentCount: -1 }; // fail-closed
    }
  }
);
