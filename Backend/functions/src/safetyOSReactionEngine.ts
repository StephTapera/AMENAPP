import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

const db = admin.firestore();

const ALLOWED_SURFACES = new Set(["post", "comment", "reply", "directMessagePreview", "quotePost", "profileBio"]);

type TriggerType =
  | "scriptureReference"
  | "prayerRequest"
  | "testimony"
  | "gratitude"
  | "wisdomPrompt"
  | "repentance"
  | "grief"
  | "encouragement"
  | "shameTone"
  | "conflictTone"
  | "unknown";

type SafetyLane = "green" | "blue" | "amber" | "red";

type TriggerResult = {
  id: string;
  type: TriggerType;
  lane: SafetyLane;
  title: string;
  message: string;
  recommendedActions: string[];
  priority: number;
  confidence: number;
  source: "serverSafetyOS";
  shouldShowDiscernmentSheet: boolean;
  shouldApplyVisualEffect: boolean;
};

function normalize(value: unknown): string {
  return typeof value === "string"
    ? value.toLowerCase().replace(/\s+/g, " ").trim().slice(0, 4000)
    : "";
}

function containsAny(text: string, patterns: string[]): boolean {
  return patterns.some((pattern) => text.includes(pattern));
}

function containsScripture(text: string): boolean {
  if (containsAny(text, ["psalm ", "psalms ", "john ", "romans ", "proverbs ", "matthew ", "genesis ", "revelation ", "scripture says", "bible says"])) {
    return true;
  }
  return /\b(?:1|2|3)?\s?[a-z]+\s\d{1,3}(?::\d{1,3}(?:-\d{1,3})?)?\b/i.test(text);
}

function trigger(result: Omit<TriggerResult, "source">): TriggerResult {
  return {...result, source: "serverSafetyOS"};
}

export function analyzeSafetyOSText(text: string, surface: string): TriggerResult[] {
  const normalized = normalize(text);
  if (!normalized) return [];

  const results: TriggerResult[] = [];

  if (containsScripture(normalized)) {
    results.push(trigger({
      id: "scripture",
      type: "scriptureReference",
      lane: "green",
      title: "Scripture detected",
      message: "Amen found a possible Scripture reference.",
      recommendedActions: ["openScripture", "addContext", "keepAsText"],
      priority: 45,
      confidence: 0.88,
      shouldShowDiscernmentSheet: false,
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["pray for me", "please pray", "need prayer", "prayer request", "keep me in prayer", "praying for you", "prayers"])) {
    results.push(trigger({
      id: "prayer",
      type: "prayerRequest",
      lane: "green",
      title: "Prayer detected",
      message: "This sounds like a prayer request.",
      recommendedActions: ["joinPrayer", "keepAsText"],
      priority: 52,
      confidence: 0.92,
      shouldShowDiscernmentSheet: false,
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["god brought me", "i was lost", "i came back to god", "i came back", "jesus saved me", "this is my testimony", "testimony"])) {
    results.push(trigger({
      id: "testimony",
      type: "testimony",
      lane: "green",
      title: "Testimony moment",
      message: "This may encourage someone through testimony.",
      recommendedActions: ["postAnyway"],
      priority: 40,
      confidence: 0.81,
      shouldShowDiscernmentSheet: false,
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["grateful to god", "thankful for god", "praise god", "so thankful", "i'm thankful", "im thankful"])) {
    results.push(trigger({
      id: "gratitude",
      type: "gratitude",
      lane: "green",
      title: "Gratitude moment",
      message: "This carries gratitude or praise.",
      recommendedActions: ["postAnyway"],
      priority: 28,
      confidence: 0.76,
      shouldShowDiscernmentSheet: false,
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["need wisdom", "help me discern", "should i", "what should i do", "before i respond", "is this wise"])) {
    results.push(trigger({
      id: "wisdom",
      type: "wisdomPrompt",
      lane: "blue",
      title: "Discernment moment",
      message: "This sounds like a wisdom prompt.",
      recommendedActions: ["pauseAndPray", "postAnyway"],
      priority: 54,
      confidence: 0.8,
      shouldShowDiscernmentSheet: false,
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["you should be ashamed", "ashamed of yourself", "fake christian", "god hates you", "worthless", "disgusting"])) {
    results.push(trigger({
      id: "shame",
      type: "shameTone",
      lane: "amber",
      title: "Discernment moment",
      message: "This may land as shame instead of correction.",
      recommendedActions: ["editWithGrace", "saveDraft", "postAnyway"],
      priority: 100,
      confidence: 0.95,
      shouldShowDiscernmentSheet: surface !== "profileBio",
      shouldApplyVisualEffect: true,
    }));
  }

  if (containsAny(normalized, ["shut up", "idiot", "i hate you", "i hate", "you always", "you never"])) {
    results.push(trigger({
      id: "conflict",
      type: "conflictTone",
      lane: "amber",
      title: "Peace check",
      message: "This may escalate conflict.",
      recommendedActions: ["rewriteGently", "pauseAndPray", "postAnyway"],
      priority: 96,
      confidence: 0.93,
      shouldShowDiscernmentSheet: true,
      shouldApplyVisualEffect: true,
    }));
  }

  return results.sort((lhs, rhs) => rhs.priority - lhs.priority || lhs.title.localeCompare(rhs.title));
}

export const canonicalizeSafetyOSReactionTriggers = onCall(
  {enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required");
    }
    const text = normalize(request.data?.text);
    const surface = typeof request.data?.surface === "string" ? request.data.surface : "";
    if (!ALLOWED_SURFACES.has(surface)) {
      throw new HttpsError("invalid-argument", "Invalid surface");
    }
    if (text.length > 4000) {
      throw new HttpsError("invalid-argument", "Text too long");
    }

    const triggers = analyzeSafetyOSText(text, surface);
    await db.collection("safetyOSCanonicalizationLogs").add({
      uid: request.auth.uid,
      surface,
      triggerTypes: triggers.map((item) => item.type),
      primaryTrigger: triggers[0]?.type ?? "none",
      triggerCount: triggers.length,
      isPublicMetric: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {triggers};
  },
);
