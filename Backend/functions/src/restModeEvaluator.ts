import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

const db = admin.firestore();

// MARK: - Types

interface RestModePolicy {
  userId: string;
  enabled: boolean;
  modeName: "lord_day" | "sunday_rest" | "sabbath_rhythm";
  modeLevel: "gentle" | "worship" | "full";
  timezone: string;
  activeDay: "sunday" | "saturday" | "custom";
  customSchedule?: {
    days: number[];   // 0=Sunday … 6=Saturday (JS Date.getDay())
    startTime: string;
    endTime: string;
  };
  startTime: string;   // "HH:mm"
  endTime: string;     // "HH:mm"
  allowedRoutes: string[];
  restrictedRoutes: string[];
  reflectionFeedEnabled: boolean;
  postingPolicy: "allowed" | "limitedTypes" | "draftOnly" | "disabled";
  commentPolicy: "open" | "toneGated" | "readOnly" | "disabled";
  notificationPolicy: {
    allowedTypes: string[];
    mutedTypes: string[];
  };
  allowTemporaryOverride: boolean;
  overrideDurationMinutes: number;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

interface RestModeStatus {
  isActive: boolean;
  policy: RestModePolicy | null;
  evaluatedAt: string;
}

// MARK: - Helpers

function parseMins(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function isWithinWindow(nowMinutes: number, start: string, end: string): boolean {
  const s = parseMins(start);
  const e = parseMins(end);
  return s <= e ? nowMinutes >= s && nowMinutes <= e : nowMinutes >= s || nowMinutes <= e;
}

function isPolicyActive(policy: RestModePolicy): boolean {
  if (!policy.enabled) return false;

  // Resolve current time in user's timezone
  const tz = policy.timezone || "UTC";
  const nowInTz = new Date(new Date().toLocaleString("en-US", { timeZone: tz }));
  const weekday = nowInTz.getDay(); // 0=Sunday, 6=Saturday
  const nowMins = nowInTz.getHours() * 60 + nowInTz.getMinutes();

  if (policy.activeDay === "custom") {
    const sched = policy.customSchedule;
    if (!sched || !sched.days.includes(weekday)) return false;
    return isWithinWindow(nowMins, sched.startTime, sched.endTime);
  }

  const targetDay = policy.activeDay === "sunday" ? 0 : 6;
  if (weekday !== targetDay) return false;
  return isWithinWindow(nowMins, policy.startTime, policy.endTime);
}

// MARK: - Callable: evaluateRestMode

export const evaluateRestMode = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<RestModeStatus> => {
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const uid = request.auth.uid;
    const snap = await db.collection("restModePolicies").doc(uid).get();

    if (!snap.exists) {
      return { isActive: false, policy: null, evaluatedAt: new Date().toISOString() };
    }

    const policy = snap.data() as RestModePolicy;
    const isActive = isPolicyActive(policy);

    return {
      isActive,
      policy: isActive ? policy : null,
      evaluatedAt: new Date().toISOString(),
    };
  }
);

// MARK: - Callable: setRestModePolicy

export const setRestModePolicy = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ success: boolean }> => {
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const uid = request.auth.uid;
    const input = request.data as Partial<RestModePolicy>;

    // Validate required fields
    if (typeof input.enabled !== "boolean") {
      throw new HttpsError("invalid-argument", "enabled must be a boolean.");
    }

    const allowedLevels = ["gentle", "worship", "full"];
    if (input.modeLevel && !allowedLevels.includes(input.modeLevel)) {
      throw new HttpsError("invalid-argument", `modeLevel must be one of: ${allowedLevels.join(", ")}.`);
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.collection("restModePolicies").doc(uid).set(
      {
        ...input,
        userId: uid,
        updatedAt: now,
        createdAt: now,  // set() with merge will not overwrite if already exists via merge below
      },
      { merge: true }
    );

    return { success: true };
  }
);

// MARK: - Firestore trigger: sync church notification policy on policy write

export const onRestModePolicyWritten = onDocumentWritten(
  {
    document: "restModePolicies/{userId}",
    region: "us-central1",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const policy = after.data() as RestModePolicy;
    if (!policy.enabled) return;

    // Write a lightweight activation record so other services can query rest mode state
    // without re-evaluating timezone logic on every read.
    const uid = event.params.userId;
    const tz = policy.timezone || "UTC";
    const nowInTz = new Date(new Date().toLocaleString("en-US", { timeZone: tz }));
    const weekday = nowInTz.getDay();
    const nowMins = nowInTz.getHours() * 60 + nowInTz.getMinutes();

    const isCurrentlyActive = isPolicyActive(policy);

    await db.collection("users").doc(uid).set(
      {
        restModeActive: isCurrentlyActive,
        restModeLevel: policy.modeLevel,
        restModeCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info(`[RestMode] active=${isCurrentlyActive} weekday=${weekday} nowMins=${nowMins}`);
  }
);

// MARK: - Callable: resolvePostAILabel
// Server-side label resolution so clients cannot manipulate required labels.

interface PostAIUsageInput {
  aiUseTypes: string[];
  userAcceptedSuggestion: boolean;
  aiGeneratedPercentageEstimate?: number;
  toneCheckSummary?: Record<string, number>;
  modelVersion?: string;
}

interface ResolvedAILabel {
  primaryLabel: string | null;
  disclosureRequired: boolean;
}

const LABEL_REQUIRED_TYPES = new Set([
  "draft_generation",
  "tone_rewrite_major",
  "translation",
  "safety_rewrite",
  "sermon_notes_summary",
]);

export const resolvePostAILabel = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<ResolvedAILabel> => {
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const input = request.data as PostAIUsageInput;
    const types: string[] = input.aiUseTypes ?? [];

    if (types.length === 0) {
      return { primaryLabel: null, disclosureRequired: false };
    }

    // Priority order: highest wins
    let label: string | null = null;

    if (types.includes("draft_generation") || types.includes("tone_rewrite_major")) {
      label = "ai_assisted_post";
    } else if (types.includes("translation")) {
      label = "translated_with_ai";
    } else if (types.includes("tone_rewrite_minor")) {
      label = "ai_assisted_tone";
    } else if (types.includes("safety_rewrite")) {
      label = "edited_for_safety";
    } else if (types.includes("sermon_notes_summary")) {
      label = "notes_summarized";
    } else if (types.includes("prayer_generation")) {
      label = "prayer_assisted";
    } else if (types.includes("scripture_suggestion")) {
      label = "scripture_suggested";
    } else if (types.includes("berean_insert")) {
      label = "berean_assisted";
    } else if (types.includes("tone_check")) {
      label = "tone_checked";
    } else if (types.includes("alt_text_generation")) {
      label = "alt_text_assisted";
    }

    const disclosureRequired = types.some((t) => LABEL_REQUIRED_TYPES.has(t));

    return { primaryLabel: label, disclosureRequired };
  }
);
