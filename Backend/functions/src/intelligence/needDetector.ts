/**
 * needDetector.ts
 *
 * Living Intelligence — Need Detection
 * Detects needs from posts, prayer requests, and announcements using AI
 * classification, then routes supply ↔ demand.
 *
 * Callables:
 *   - classifyPostNeed: classify a post's need type, write need doc if actionable
 *   - matchNeedsToVolunteers: match church needs to volunteers/donors (opt-in only)
 *
 * Invariants:
 *   - Moderation runs before any Firestore write
 *   - Fail-closed: Anthropic down → needType=NONE, no need created
 *   - No behavioral profiling, no spectacle counters
 *   - opt-in gated for matchNeedsToVolunteers
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import type {
  IntelligenceCard,
  CardAction,
  BackingEntity,
  ActionRung,
} from "./contracts";
import { callModel, moderateContent, ANTHROPIC_API_KEY } from "./amenRouting";

const db = admin.firestore();

// ─── Types ─────────────────────────────────────────────────────────────────────

type NeedType =
  | "MATERIAL"
  | "PRAYER"
  | "VOLUNTEER"
  | "DONATION"
  | "COMMUNITY"
  | "INFORMATION"
  | "NONE";

type Urgency = "low" | "medium" | "high";

interface ClassifyPostNeedRequest {
  postId: string;
  postText: string;
  churchId?: string;
}

interface NeedClassification {
  needType: NeedType;
  confidence: number;
  urgency: Urgency;
  actionable: boolean;
}

interface NeedDoc {
  needType: NeedType;
  sourcePostId: string;
  churchId?: string;
  urgency: Urgency;
  submitterUid: string;
  isDeleted: boolean;
  createdAt: admin.firestore.FieldValue;
}

// ─── Fail-closed classifier ────────────────────────────────────────────────────

// Maps callModel classify_need output (IMMEDIATE/THIS_WEEK/ONGOING) to local urgency
function mapUrgency(raw: string): Urgency {
  if (raw === "IMMEDIATE") return "high";
  if (raw === "THIS_WEEK") return "medium";
  if (raw === "ONGOING" || raw === "low" || raw === "medium" || raw === "high") {
    return (raw as Urgency) in { low: 1, medium: 1, high: 1 } ? (raw as Urgency) : "low";
  }
  return "low";
}

async function classifyNeed(text: string, userId: string): Promise<NeedClassification> {
  const failClosed: NeedClassification = {
    needType: "NONE",
    confidence: 0,
    urgency: "low",
    actionable: false,
  };

  try {
    const output = await callModel({
      task: "intelligence.classify_need",
      input: text.slice(0, 800),
      userId,
    });

    if (output.error || !output.result) {
      console.warn("classifyNeed: callModel returned error —", output.error);
      return failClosed;
    }

    const parsed = output.result as Partial<{
      needType: string;
      confidence: number;
      urgency: string;
      actionable: boolean;
    }>;

    const validTypes: NeedType[] = [
      "MATERIAL", "PRAYER", "VOLUNTEER", "DONATION", "COMMUNITY", "INFORMATION", "NONE",
      // callModel uses RESOURCE/PRESENCE/SKILL — map unknowns to NONE
    ];
    const validUrgencies: Urgency[] = ["low", "medium", "high"];

    const urgencyRaw = parsed.urgency ?? "low";
    return {
      needType: validTypes.includes(parsed.needType as NeedType)
        ? (parsed.needType as NeedType)
        : "NONE",
      confidence: typeof parsed.confidence === "number"
        ? Math.max(0, Math.min(1, parsed.confidence))
        : 0,
      urgency: validUrgencies.includes(mapUrgency(urgencyRaw))
        ? mapUrgency(urgencyRaw)
        : "low",
      actionable: typeof parsed.actionable === "boolean" ? parsed.actionable : false,
    };
  } catch (err) {
    console.error("classifyNeed: error —", err);
    return failClosed;
  }
}

// ─── Action builder ────────────────────────────────────────────────────────────

function actionsForNeedType(needType: NeedType, needId: string): CardAction[] {
  const pairs: Array<[ActionRung, string, string]> = [];

  switch (needType) {
    case "MATERIAL":
      pairs.push(["GIVE", "Give Resources", "action.giveToNeed"]);
      pairs.push(["SHOW_UP", "Help Out", "action.volunteer"]);
      break;
    case "PRAYER":
      pairs.push(["PRAY", "Pray for This", "action.addToPrayer"]);
      break;
    case "VOLUNTEER":
      pairs.push(["SHOW_UP", "Volunteer", "action.volunteer"]);
      break;
    case "DONATION":
      pairs.push(["GIVE", "Give", "action.giveToNeed"]);
      break;
    case "COMMUNITY":
      pairs.push(["DISCUSS", "Join the Conversation", "action.discuss"]);
      pairs.push(["SHOW_UP", "Show Up", "action.volunteer"]);
      break;
    case "INFORMATION":
      pairs.push(["LEARN", "Learn More", "action.openNeed"]);
      pairs.push(["DISCUSS", "Share Guidance", "action.discuss"]);
      break;
    default:
      pairs.push(["NOTICE", "View Need", "action.openNeed"]);
  }

  return pairs.map(([rung, label, handler]) => ({
    rung,
    label,
    handler,
    target: needId,
  }));
}

// ─── Callable: classifyPostNeed ────────────────────────────────────────────────

export const classifyPostNeed = onCall({ enforceAppCheck: true, secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 45,
    memory: "256MiB", }, async (request) => {
    // 1. Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    // 2. Rate limit
    await enforceRateLimit(uid, [
      RATE_LIMITS.AI_PER_MINUTE,
      RATE_LIMITS.AI_PER_DAY,
    ]);

    const { postId, postText, churchId } = request.data as ClassifyPostNeedRequest;

    if (!postId || !postText) {
      throw new HttpsError("invalid-argument", "postId and postText are required.");
    }

    // 3. Moderation check — fail-closed: if moderation is down, refuse
    const modResult = await moderateContent(postText);
    if (!modResult.safe) {
      return { created: false, reason: "moderation" };
    }

    // 4. Classify need (fail-closed)
    const classification = await classifyNeed(postText, uid);

    // 5. If not actionable or low confidence → no need created
    if (!classification.actionable || classification.confidence <= 0.7) {
      return { created: false, classification };
    }

    if (classification.needType === "NONE") {
      return { created: false, classification };
    }

    // 6. Write need doc
    const needRef = db.collection("needs").doc();
    const needId = needRef.id;

    const needDoc: NeedDoc = {
      needType: classification.needType,
      sourcePostId: postId,
      ...(churchId ? { churchId } : {}),
      urgency: classification.urgency,
      submitterUid: uid,
      isDeleted: false,
      createdAt: FieldValue.serverTimestamp(),
    };

    await needRef.set(needDoc);

    // 7. Build IntelligenceCard
    const now = Date.now();
    const expiresAt = now + 14 * 24 * 60 * 60 * 1000; // 14 days

    const backingEntity: BackingEntity = {
      kind: "NEED",
      id: needId,
      verified: false, // Needs human verification for VERIFIED status
    };

    const actions = actionsForNeedType(classification.needType, needId);

    const urgencyLabel =
      classification.urgency === "high" ? "Urgent need" : "Community need";

    const card: IntelligenceCard = {
      id: `need_card_${needId}`,
      tier: "COMMUNITY",
      title: urgencyLabel,
      summary: [
        `${classification.needType.charAt(0) + classification.needType.slice(1).toLowerCase()} need shared`,
        "Shared by community",
        churchId ? "From your church" : "From your network",
      ].slice(0, 3),
      backingEntity,
      truthLevel: "COMMUNITY_CONFIRMED",
      actions,
      rankScore: classification.urgency === "high" ? 75 : 50,
      rankReasons: [
        "Community-submitted need",
        `Classified as ${classification.needType}`,
        `Urgency: ${classification.urgency}`,
      ],
      formation: {
        finite: true,
        spectacleCounters: false,
      },
      createdAt: now,
      expiresAt,
    };

    return { created: true, needId, classification, card };
  }
);

// ─── Callable: matchNeedsToVolunteers ──────────────────────────────────────────

export const matchNeedsToVolunteers = onCall({ enforceAppCheck: true, timeoutSeconds: 30,
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

    const { churchId } = request.data as { churchId: string };

    if (!churchId) {
      throw new HttpsError("invalid-argument", "churchId is required.");
    }

    // 3. Opt-in check — user must have opted in
    const userSnap = await db.collection("users").doc(uid).get();
    const volunteerMatchingEnabled =
      (userSnap.data() as Record<string, unknown> | undefined)?.volunteerMatchingEnabled === true;
    if (!volunteerMatchingEnabled) {
      throw new HttpsError(
        "failed-precondition",
        "Volunteer matching is not enabled for this user."
      );
    }

    // 4. Fetch active needs for the church
    const needsSnap = await db
      .collection("needs")
      .where("churchId", "==", churchId)
      .where("isDeleted", "==", false)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    // 5. Fetch volunteer opportunities for the church
    const oppsSnap = await db
      .collection("volunteerOpportunities")
      .where("churchId", "==", churchId)
      .where("isActive", "==", true)
      .limit(20)
      .get();

    const now = Date.now();
    const cards: IntelligenceCard[] = [];

    // 6. Route: People → Resources (MATERIAL needs)
    for (const needDoc of needsSnap.docs) {
      const need = needDoc.data() as NeedDoc & { id: string };
      const needId = needDoc.id;
      const actions = actionsForNeedType(need.needType, needId);

      const backingEntity: BackingEntity = {
        kind: "NEED",
        id: needId,
        verified: false,
      };

      const urgencyLabel = need.urgency === "high" ? "Urgent" : "Active";

      cards.push({
        id: `need_volunteer_card_${needId}`,
        tier: "COMMUNITY",
        title: `${urgencyLabel} church need`,
        summary: [
          `${need.needType.charAt(0) + need.needType.slice(1).toLowerCase()} need from your church`,
          "Your involvement can make a difference",
        ],
        backingEntity,
        truthLevel: "COMMUNITY_CONFIRMED",
        actions,
        rankScore: need.urgency === "high" ? 80 : 55,
        rankReasons: [
          "From your church",
          `Need type: ${need.needType}`,
        ],
        formation: {
          finite: true,
          spectacleCounters: false,
        },
        createdAt: now,
        expiresAt: now + 7 * 24 * 60 * 60 * 1000,
      });
    }

    // 7. Route: Volunteers → Opportunities
    for (const oppDoc of oppsSnap.docs) {
      const opp = oppDoc.data() as {
        title?: string;
        description?: string;
        churchId: string;
      };
      const oppId = oppDoc.id;

      const backingEntity: BackingEntity = {
        kind: "ORG",
        id: oppId,
        verified: true,
      };

      cards.push({
        id: `opp_card_${oppId}`,
        tier: "COMMUNITY",
        title: opp.title ?? "Volunteer opportunity",
        summary: [
          opp.description ? opp.description.slice(0, 80) : "Help your church community",
          "From your church",
        ],
        backingEntity,
        truthLevel: "CHURCH_CONFIRMED",
        actions: [
          {
            rung: "SHOW_UP",
            label: "Volunteer",
            handler: "action.volunteer",
            target: oppId,
          },
        ],
        rankScore: 60,
        rankReasons: [
          "Volunteer opportunity from your church",
        ],
        formation: {
          finite: true,
          spectacleCounters: false,
        },
        createdAt: now,
        expiresAt: now + 30 * 24 * 60 * 60 * 1000,
      });
    }

    // Sort by rankScore descending
    cards.sort((a, b) => b.rankScore - a.rankScore);

    return { cards: cards.slice(0, 10) };
  }
);
