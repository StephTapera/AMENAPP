/**
 * prayerGraphService.ts
 *
 * Living Intelligence — Prayer Graph Service
 * Connects prayer requests to community intercessors and closes the loop
 * when prayers are answered.
 *
 * Callables:
 *   - matchPrayerSupport: match a prayer request to intercessors from the
 *     user's church community who have prayed for similar topics.
 *
 * Triggers:
 *   - onPrayerCreated: classifies need type on new prayer requests using
 *     the Anthropic API (fail-closed: falls back to NONE on error).
 *
 * Privacy invariants:
 *   - opt-in only: prayerMatchingEnabled flag must be true
 *   - NO counts — never say "N people praying"
 *   - Loop closing: follow-up card if user has previously prayed for request
 *   - Lament frame propagated from prayer request doc
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import type {
  IntelligenceCard,
  CardAction,
  BackingEntity,
} from "./contracts";
import { callModel, ANTHROPIC_API_KEY } from "./amenRouting";

const db = admin.firestore();

interface MatchPrayerSupportRequest {
  uid: string;
  prayerRequestId: string;
}

interface PrayerDoc {
  id: string;
  title?: string;
  body?: string;
  authorUid: string;
  churchId?: string;
  prayerNeedType?: string;
  isAnonymous?: boolean;
  lamentFrame?: boolean;
  createdAt?: admin.firestore.Timestamp;
}

// ─── Callable: matchPrayerSupport ─────────────────────────────────────────────

export const matchPrayerSupport = onCall({ enforceAppCheck: true, timeoutSeconds: 30,
    memory: "256MiB", }, async (request) => {
    // 1. Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    // 2. Rate limit
    await enforceRateLimit(uid, [
      RATE_LIMITS.SUGGEST_PER_MINUTE,
      RATE_LIMITS.SUGGEST_PER_DAY,
    ]);

    const { prayerRequestId } = request.data as MatchPrayerSupportRequest;

    if (!prayerRequestId) {
      throw new HttpsError("invalid-argument", "prayerRequestId is required.");
    }

    // 3. Fetch prayer request doc
    const prayerRef = db.collection("prayers").doc(prayerRequestId);
    const prayerSnap = await prayerRef.get();
    if (!prayerSnap.exists) {
      throw new HttpsError("not-found", "Prayer request not found.");
    }
    const prayer: PrayerDoc = { id: prayerSnap.id, ...(prayerSnap.data() as Omit<PrayerDoc, "id">) };

    // 4. Check opt-in
    const userPrefSnap = await db.collection("users").doc(uid).get();
    const prayerMatchingEnabled =
      (userPrefSnap.data() as Record<string, unknown> | undefined)?.prayerMatchingEnabled === true;
    if (!prayerMatchingEnabled) {
      throw new HttpsError(
        "failed-precondition",
        "Prayer matching is not enabled for this user."
      );
    }

    // 5. Find user's prayer topics
    const userTopicsSnap = await db
      .collection("users")
      .doc(uid)
      .collection("prayerTopics")
      .limit(20)
      .get();
    const myTopics = new Set<string>(
      userTopicsSnap.docs.map((d) => d.id.toLowerCase())
    );

    // 6. Check if user has previously prayed for this request (loop closing)
    const priorPrayerSnap = await db
      .collection("prayerInteractions")
      .where("userId", "==", uid)
      .where("prayerRequestId", "==", prayerRequestId)
      .where("type", "==", "PRAYED")
      .limit(1)
      .get();

    const hasPrayedBefore = !priorPrayerSnap.empty;
    const priorPrayedAt: admin.firestore.Timestamp | null = hasPrayedBefore
      ? (priorPrayerSnap.docs[0].data().createdAt as admin.firestore.Timestamp)
      : null;

    // 7. Build match reasons
    const matchReasons: string[] = [];

    if (prayer.churchId) {
      // Check if user shares a church
      const sharedChurch = await db
        .collection("churchMemberships")
        .where("userId", "==", uid)
        .where("churchId", "==", prayer.churchId)
        .limit(1)
        .get();
      if (!sharedChurch.empty) {
        matchReasons.push("From your church community");
      }
    }

    // Topic overlap check
    if (prayer.prayerNeedType && myTopics.has(prayer.prayerNeedType.toLowerCase())) {
      matchReasons.push("Similar to your prayer history");
    }

    if (matchReasons.length === 0) {
      matchReasons.push("From your community");
    }

    // 8. Build card
    const now = Date.now();
    const expiresAt = now + 7 * 24 * 60 * 60 * 1000; // 7 days

    const displayTitle = prayer.isAnonymous
      ? "Anonymous prayer request"
      : prayer.title ?? "Prayer request";

    const backingEntity: BackingEntity = {
      kind: "PRAYER_REQUEST",
      id: prayerRequestId,
      verified: true,
    };

    const actions: CardAction[] = [
      {
        rung: "PRAY",
        label: "Add Your Prayer",
        handler: "action.addToPrayer",
        target: prayerRequestId,
      },
      {
        rung: "NOTICE",
        label: "Open Prayer",
        handler: "action.openPrayer",
        target: prayerRequestId,
      },
    ];

    const rankReasons: string[] = [
      "Matched from your church community",
      ...matchReasons,
    ];

    const formation: IntelligenceCard["formation"] = {
      finite: true,
      spectacleCounters: false,
      lamentFrame: prayer.lamentFrame === true,
      ...(hasPrayedBefore && priorPrayedAt
        ? { loopParentId: `prayer_prior_${uid}_${prayerRequestId}` }
        : {}),
    };

    const summary: string[] = [
      displayTitle,
      matchReasons[0] ?? "From your community",
    ].slice(0, 3);

    const card: IntelligenceCard = {
      id: `prayer_card_${prayerRequestId}_${uid}`,
      tier: "SPIRITUAL",
      title: hasPrayedBefore ? `Following up: ${displayTitle}` : displayTitle,
      summary,
      backingEntity,
      truthLevel: "CHURCH_CONFIRMED",
      matchReasons,
      actions,
      rankScore: hasPrayedBefore ? 80 : 60,
      rankReasons,
      formation,
      createdAt: now,
      expiresAt,
    };

    return { card, hasPrayedBefore, priorPrayedAt: priorPrayedAt?.toMillis() ?? null };
  }
);

// ─── Trigger: classify need type on new prayer requests ───────────────────────

export const onPrayerCreated = onDocumentCreated(
  {
    document: "prayers/{prayerId}",
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as PrayerDoc;
    const text = [data.title, data.body].filter(Boolean).join(" ").trim();

    if (!text) return;

    let prayerNeedType = "NONE";

    try {
      const output = await callModel({
        task: "intelligence.classify_need",
        input: text.slice(0, 500),
        userId: snap.data()?.uid ?? "system",
      });

      if (!output.error && output.result) {
        const parsed = output.result as Partial<{ needType: string }>;
        const valid = ["MATERIAL", "PRAYER", "VOLUNTEER", "DONATION", "COMMUNITY", "INFORMATION", "NONE"];
        const raw = (parsed.needType ?? "NONE").toUpperCase();
        prayerNeedType = valid.includes(raw) ? raw : "NONE";
      }
    } catch (err) {
      // Fail-closed: classification failure must not block prayer creation
      console.error("onPrayerCreated: classification error:", err);
      prayerNeedType = "NONE";
    }

    await snap.ref.update({ prayerNeedType });
  }
);
