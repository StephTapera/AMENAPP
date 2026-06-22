import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

const db = admin.firestore();

// Shared guards
function requireAuth(request: CallableRequest): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  return request.auth.uid;
}
function requireAppCheck(request: CallableRequest): void {
  if (!request.app) throw new HttpsError("failed-precondition", "App Check required.");
}

// ============================================================
// FEATURE 1: UNSENT THOUGHTS
// ============================================================

export const detectUnsentThoughtRisk = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { textLength, surface, clientFlags, hourOfDay } = request.data as {
    textLength: number;
    surface: string;
    clientFlags: string[];
    hourOfDay: number;
  };

  void surface;

  const riskFlags: string[] = [...(clientFlags || [])];
  let emotionalIntensityScore = 0.0;
  let suggestedAction: string | null = null;

  // Server-side heuristics (no raw text stored or logged)
  if (hourOfDay >= 22 || hourOfDay <= 4) {
    if (!riskFlags.includes("late_night")) riskFlags.push("late_night");
  }
  if (textLength > 500) {
    if (!riskFlags.includes("long_draft")) riskFlags.push("long_draft");
  }

  emotionalIntensityScore = Math.min(riskFlags.length / 5.0, 1.0);

  if (riskFlags.includes("conflict_language") || riskFlags.includes("shame_language")) {
    suggestedAction = "run_peace_check";
  } else if (riskFlags.includes("late_night") && riskFlags.length > 1) {
    suggestedAction = "revisit_later";
  } else if (riskFlags.length >= 2) {
    suggestedAction = "save_draft";
  }

  return {
    riskFlags,
    emotionalIntensityScore,
    suggestedAction,
    // Analytics event: never logs raw text
    analyzedAt: admin.firestore.Timestamp.now().toDate().toISOString()
  };
});

export const saveUnsentThought = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { sourceSurface, emotionalIntensityScore, riskFlags, suggestedAction } = request.data as {
    sourceSurface: string;
    emotionalIntensityScore: number;
    riskFlags: string[];
    suggestedAction?: string;
  };

  if (!sourceSurface) throw new HttpsError("invalid-argument", "sourceSurface required.");

  const docRef = await db.collection("users").doc(uid).collection("unsentThoughts").add({
    userId: uid,
    sourceSurface,
    draftText: "", // Raw text intentionally not stored server-side
    emotionalIntensityScore: emotionalIntensityScore || 0.0,
    riskFlags: riskFlags || [],
    suggestedAction: suggestedAction || null,
    resolvedAt: null,
    resolutionType: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { id: docRef.id };
});

export const resolveUnsentThought = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { thoughtId, resolutionType } = request.data as { thoughtId: string; resolutionType: string };

  const validResolutions = ["continued_writing", "saved_draft", "turned_to_prayer", "peace_checked", "revisited", "shared"];
  if (!validResolutions.includes(resolutionType)) {
    throw new HttpsError("invalid-argument", "Invalid resolution type.");
  }

  await db.collection("users").doc(uid).collection("unsentThoughts").doc(thoughtId).update({
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolutionType,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});

// ============================================================
// FEATURE 2: SCRIPTURE DRIFT
// ============================================================

export const analyzeScriptureDrift = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  // Analyze recent scripture usage patterns from user's public posts
  // This runs as a background job — returns immediately, writes signal if pattern found
  try {
    // Fetch recent posts with scripture references
    const postsSnapshot = await db.collection("posts")
      .where("userId", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();

    const posts = postsSnapshot.docs.map(d => d.data());
    const scriptureRefs: string[] = [];

    posts.forEach(post => {
      if (post["scriptureRefs"]) scriptureRefs.push(...post["scriptureRefs"]);
    });

    // Heuristic analysis (real system would use AI here)
    // For now: detect obvious patterns
    let signalType: string | null = null;
    let confidence = 0.0;

    if (scriptureRefs.length < 3) {
      return { analyzed: true, signalFound: false };
    }

    // Grace/truth balance heuristic
    const graceRefs = scriptureRefs.filter(r =>
      r.toLowerCase().includes("grace") ||
      r.toLowerCase().includes("john 3") ||
      r.toLowerCase().includes("romans 8")
    ).length;
    const truthRefs = scriptureRefs.filter(r =>
      r.toLowerCase().includes("proverbs") ||
      r.toLowerCase().includes("james") ||
      r.toLowerCase().includes("matthew 7")
    ).length;

    if (graceRefs > 0 && truthRefs === 0 && scriptureRefs.length >= 8) {
      signalType = "grace_without_truth";
      confidence = Math.min(0.45 + (graceRefs * 0.04), 0.75);
    } else if (truthRefs > 0 && graceRefs === 0 && scriptureRefs.length >= 8) {
      signalType = "truth_without_grace";
      confidence = Math.min(0.45 + (truthRefs * 0.04), 0.75);
    }

    if (signalType && confidence >= 0.5) {
      // Check if we already have this signal type recently
      const existingQuery = await db.collection("users").doc(uid)
        .collection("scriptureDriftSignals")
        .where("signalType", "==", signalType)
        .where("dismissed", "==", false)
        .limit(1)
        .get();

      if (existingQuery.empty) {
        await db.collection("users").doc(uid).collection("scriptureDriftSignals").add({
          userId: uid,
          signalType,
          confidence,
          evidenceSummary: null, // Not storing post content
          balancingScriptureSuggestions: [],
          recommendedReflection: null,
          relatedThreadIds: postsSnapshot.docs.slice(0, 5).map(d => d.id),
          scriptureRefs: scriptureRefs.slice(0, 10),
          dismissed: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
    }

    return { analyzed: true, signalFound: signalType !== null };
  } catch (error) {
    logger.error("analyzeScriptureDrift error", error);
    return { analyzed: false, signalFound: false };
  }
});

export const generateBalancingScripture = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { signalType } = request.data as { signalId: string; signalType?: string };

  // Hardcoded balancing suggestions by type (in production: use AI)
  const balancingMap: Record<string, string[]> = {
    grace_without_truth: [
      "John 1:14 — full of grace and truth",
      "Ephesians 4:15 — speaking the truth in love",
      "Proverbs 27:6 — faithful are the wounds of a friend"
    ],
    truth_without_grace: [
      "Romans 5:8 — while we were still sinners",
      "Ephesians 2:8 — saved by grace through faith",
      "Luke 15:20 — the father ran to his son"
    ],
    self_justification: [
      "Proverbs 21:2 — every way of a man is right in his own eyes",
      "James 1:19 — be quick to hear, slow to speak",
      "Psalm 139:23-24 — search me, O God"
    ],
    avoids_forgiveness: [
      "Matthew 18:21-22 — forgive seventy times seven",
      "Colossians 3:13 — forgiving each other",
      "Luke 6:37 — forgive and you will be forgiven"
    ],
    condemnation_language: [
      "Romans 8:1 — no condemnation in Christ",
      "John 3:17 — not sent to condemn",
      "Matthew 7:1-2 — judge not"
    ],
    selective_use: [
      "2 Timothy 3:16 — all scripture is profitable",
      "Acts 20:27 — the whole counsel of God",
      "Psalm 119:160 — all your words are true"
    ],
    distorted_application: [
      "2 Peter 1:20 — no prophecy of private interpretation",
      "2 Timothy 2:15 — rightly dividing the word",
      "Acts 17:11 — examining the scriptures daily"
    ]
  };

  const key = signalType && balancingMap[signalType] ? signalType : "grace_without_truth";
  return { scriptures: balancingMap[key] };
});

export const dismissDriftSignal = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { signalId } = request.data as { signalId: string };

  await db.collection("users").doc(uid).collection("scriptureDriftSignals").doc(signalId)
    .update({ dismissed: true });

  return { success: true };
});

// ============================================================
// FEATURE 3: SILENCE INTELLIGENCE
// ============================================================

export const detectSilencePatterns = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  // Run a scan of user's avoidance patterns across saved items
  const silenceSignalsRef = db.collection("users").doc(uid).collection("silenceSignals");
  const snapshot = await silenceSignalsRef
    .where("status", "==", "active")
    .where("avoidanceCount", ">=", 3)
    .get();

  type SilenceSignal = { id: string; suggestedAction?: string; targetType?: string };
  const signals: SilenceSignal[] = snapshot.docs.map(d => ({ id: d.id, ...(d.data() as Record<string, unknown>) } as SilenceSignal));

  // Generate gentle prompts for high-avoidance signals
  for (const signal of signals) {
    if (!signal.suggestedAction) {
      let prompt: string;
      switch (signal.targetType) {
        case "prayer_thread":
          prompt = "You've passed by this prayer a few times. Want help approaching it?";
          break;
        case "saved_verse":
          prompt = "This verse is still here when you're ready.";
          break;
        case "walk_with_christ_path":
          prompt = "Your path is waiting. Even a few minutes matters.";
          break;
        default:
          prompt = "This keeps coming back. It might be worth a moment.";
      }

      await silenceSignalsRef.doc(signal.id).update({
        suggestedAction: prompt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }

  return { scanned: true, patternsFound: signals.length };
});

export const resurfaceAvoidedItem = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { targetType, targetId } = request.data as { targetType: string; targetId: string };

  const docId = `${targetType}_${targetId}`;
  await db.collection("users").doc(uid).collection("silenceSignals").doc(docId).update({
    avoidanceCount: admin.firestore.FieldValue.increment(1),
    lastAvoidedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});

export const markSilenceSignalResolved = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { signalId } = request.data as { signalId: string };

  await db.collection("users").doc(uid).collection("silenceSignals").doc(signalId).update({
    status: "resolved",
    resolvedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});

// ============================================================
// FEATURE 4: RELATIONAL GRAVITY
// ============================================================

export const updateRelationalGravity = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { personId, interactionType } = request.data as {
    personId: string;
    interactionType: string;
  };

  const nodeRef = db.collection("users").doc(uid).collection("relationalGravityNodes").doc(personId);
  const snapshot = await nodeRef.get();

  if (!snapshot.exists) {
    return { updated: false, reason: "Node not found" };
  }

  const updates: Record<string, unknown> = {
    lastInteractionAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  if (interactionType === "encouragement") {
    updates["encouragementScore"] = admin.firestore.FieldValue.increment(0.05);
  } else if (interactionType === "conflict") {
    updates["conflictScore"] = admin.firestore.FieldValue.increment(0.08);
  } else if (interactionType === "prayer") {
    updates["prayerCount"] = admin.firestore.FieldValue.increment(1);
  }

  await nodeRef.update(updates);

  // Re-classify state after update
  const updated = (await nodeRef.get()).data();
  if (updated) {
    const state = classifyRelationshipStateLocal(updated);
    await nodeRef.update({
      currentState: state.state,
      stateConfidence: state.confidence
    });
  }

  return { updated: true };
});

function classifyRelationshipStateLocal(data: Record<string, unknown>): { state: string; confidence: number } {
  const encouragement = (data["encouragementScore"] as number) || 0;
  const conflict = (data["conflictScore"] as number) || 0;
  const prayers = (data["prayerCount"] as number) || 0;
  const unresolved = ((data["unresolvedThreadIds"] as string[]) || []).length;

  if (conflict > 0.6 && unresolved > 0) return { state: "unresolved", confidence: 0.8 };
  if (conflict > 0.4) return { state: "tense", confidence: Math.min(0.5 + conflict * 0.5, 0.9) };
  if (prayers > 5 && encouragement > 0.5) return { state: "peaceful", confidence: 0.75 };
  if (encouragement > 0.6) return { state: "growing", confidence: 0.7 };
  if (!data["lastInteractionAt"]) return { state: "drifting", confidence: 0.5 };
  return { state: "peaceful", confidence: 0.5 };
}

export const classifyRelationshipState = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { nodeId } = request.data as { nodeId: string };

  const snapshot = await db.collection("users").doc(uid)
    .collection("relationalGravityNodes").doc(nodeId).get();

  if (!snapshot.exists) throw new HttpsError("not-found", "Node not found.");

  const data = snapshot.data()!;
  const result = classifyRelationshipStateLocal(data);

  await snapshot.ref.update({
    currentState: result.state,
    stateConfidence: result.confidence,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return result;
});

export const generateReconciliationPrompt = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { nodeId } = request.data as { nodeId: string };

  const snapshot = await db.collection("users").doc(uid)
    .collection("relationalGravityNodes").doc(nodeId).get();

  if (!snapshot.exists) throw new HttpsError("not-found", "Node not found.");

  const data = snapshot.data()!;
  const state = data["currentState"] as string;
  const name = (data["displayName"] as string) || "this person";

  const prompts: Record<string, string> = {
    tense: `Consider reaching out to ${name} without an agenda. A simple "I've been thinking about you" can open a door.`,
    unresolved: `What would it look like to take one small step toward resolution with ${name}? You don't have to resolve everything — one honest conversation can shift things.`,
    drifting: `It may be worth checking in with ${name}. Relationships drift slowly when we stop being intentional.`,
    needs_prayer: `Praying for ${name} first, before reaching out, can change how you approach them. Consider making this a practice for a few days.`,
    default: `Take a moment to reflect on your relationship with ${name}. What would you want it to look like in six months?`
  };

  return { prompt: prompts[state] || prompts["default"] };
});

// ============================================================
// FEATURE 5: MOMENT INTERCEPTION
// ============================================================

export const evaluateMomentRisk = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { triggers } = request.data as {
    textLength: number;
    surface: string;
    triggers: string[];
    hourOfDay: number;
  };

  let riskScore = 0.0;
  const weights: Record<string, number> = {
    late_night_posting: 0.25,
    rapid_typing: 0.15,
    repeated_delete_rewrite: 0.2,
    high_anger_score: 0.35,
    spiritual_manipulation_risk: 0.4,
    harsh_public_correction: 0.3,
    impulsive_send: 0.2
  };

  triggers.forEach((t: string) => { riskScore += weights[t] || 0.1; });
  riskScore = Math.min(riskScore, 1.0);

  const shouldIntercept = riskScore > 0.5;

  return {
    riskScore,
    shouldIntercept,
    triggerCount: triggers.length
  };
});

export const logMomentInterception = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { triggerType, sourceSurface, riskScore, userAction } = request.data as {
    triggerType: string;
    sourceSurface: string;
    riskScore: number;
    userAction: string;
  };

  await db.collection("users").doc(uid).collection("momentInterceptions").add({
    userId: uid,
    triggerType,
    sourceSurface,
    riskScore,
    userAction,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { logged: true };
});

export const updateMomentLearning = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  // Aggregate learning: which actions users take after intercepts
  const snapshot = await db.collection("users").doc(uid)
    .collection("momentInterceptions")
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();

  const actions = snapshot.docs.map(d => d.data()["userAction"]);
  const breathedCount = actions.filter(a => a === "breathed").length;
  const continuedCount = actions.filter(a => a === "continued_anyway").length;

  // If user mostly continues anyway, reduce intercept frequency
  // (store this preference so client-side can adjust threshold)
  await db.collection("users").doc(uid).collection("momentLearning").doc("summary").set({
    totalInterceptions: actions.length,
    breathedCount,
    continuedCount,
    preferredResponse: breathedCount > continuedCount ? "pause" : "continue",
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  return { updated: true };
});

// ============================================================
// FEATURE 6: POST-ACTION REFLECTION
// ============================================================

export const createReflectionPrompt = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { sourceActionId, actionType } = request.data as {
    sourceActionId: string;
    actionType: string;
  };

  const questionMap: Record<string, string> = {
    sent_sensitive_message: "How do you feel about how that conversation went?",
    posted_public_thought: "Did your words match your intent?",
    resolved_conflict: "Would you handle anything differently?",
    completed_prayer: "What did you sense during that prayer?",
    finished_walk_with_christ: "What stood out to you today?",
    made_discernment_decision: "What helped you reach that decision?"
  };

  const prompt = questionMap[actionType] || "How do you feel about what just happened?";

  const docRef = await db.collection("users").doc(uid).collection("postActionReflections").add({
    userId: uid,
    sourceActionId,
    actionType,
    prompt,
    completedAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { reflectionId: docRef.id, prompt };
});

export const savePostActionReflection = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { sourceActionId, actionType } = request.data as {
    sourceActionId: string;
    actionType: string;
    // Note: reflection text is stored client-side only. Server receives only IDs.
  };

  // Server records that a reflection happened (for growth pattern tracking)
  // without storing the actual private text
  await db.collection("users").doc(uid).collection("growthPatterns").doc("summary").set({
    lastReflectionAt: admin.firestore.FieldValue.serverTimestamp(),
    reflectionCount: admin.firestore.FieldValue.increment(1),
    [`${actionType}Count`]: admin.firestore.FieldValue.increment(1)
  }, { merge: true });

  // Suppress unused variable warning — sourceActionId is part of the API contract
  void sourceActionId;

  return { saved: true };
});

export const updateUserGrowthPattern = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { actionType, lessonLearned } = request.data as {
    actionType: string;
    lessonLearned?: string; // Optional: client may send if user consents
  };

  await db.collection("users").doc(uid).collection("growthPatterns").doc(actionType).set({
    actionType,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    count: admin.firestore.FieldValue.increment(1)
  }, { merge: true });

  // Suppress unused variable warning — lessonLearned is part of the API contract
  void lessonLearned;

  return { updated: true };
});

// ============================================================
// FEATURE 7: TRUTH VS EMOTION
// ============================================================

export const analyzeTruthVsEmotion = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { text } = request.data as { text: string };

  if (!text || text.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Text is required.");
  }

  // In production: call OpenAI/Claude here
  // For now: structured heuristic response
  // IMPORTANT: Raw text is NOT stored or logged

  const emotionalClaim = extractEmotionalClaim(text);
  const factualPossibility = reframeAsFact(text);
  const assumptions = detectAssumptions(text);
  const reframes = generateReframes();
  const scriptureAnchor = suggestScriptureAnchor(text);

  return {
    emotionalClaim,
    factualPossibility,
    assumptions,
    reframes,
    scriptureAnchor,
    scriptureText: null // Would be populated by Bible API in production
  };
});

function extractEmotionalClaim(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes("disrespect")) return "They disrespected me.";
  if (lower.includes("ignore") || lower.includes("ignored")) return "They ignored me.";
  if (lower.includes("wrong")) return "They were wrong.";
  if (lower.includes("hurt")) return "I was hurt by this.";
  return "Something felt wrong.";
}

function reframeAsFact(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes("disrespect")) return "They may have disagreed with your point.";
  if (lower.includes("ignore")) return "They may not have seen your message yet.";
  if (lower.includes("wrong")) return "They may have a different understanding.";
  if (lower.includes("hurt")) return "You experienced pain, though their intent may have differed.";
  return "There may be more context to understand.";
}

function detectAssumptions(text: string): string[] {
  const assumptions: string[] = [];
  const lower = text.toLowerCase();
  if (lower.includes("always") || lower.includes("never")) {
    assumptions.push("The words 'always' or 'never' may involve a generalization.");
  }
  if (lower.includes("they think") || lower.includes("they believe")) {
    assumptions.push("Assuming what they think may not reflect their actual perspective.");
  }
  if (lower.includes("obviously") || lower.includes("clearly")) {
    assumptions.push("What feels obvious to you may not be clear to them.");
  }
  if (assumptions.length === 0) {
    assumptions.push("This may involve an assumption about their intent.");
  }
  return assumptions;
}

function generateReframes(): string[] {
  return [
    "Could there be a misunderstanding that a direct conversation could clear up?",
    "What might they have been experiencing in that moment?",
    "Is there a way to approach this with curiosity rather than certainty?"
  ];
}

function suggestScriptureAnchor(text: string): string | null {
  const lower = text.toLowerCase();
  if (lower.includes("angry") || lower.includes("anger")) return "Ephesians 4:26";
  if (lower.includes("hurt") || lower.includes("pain")) return "Psalm 34:18";
  if (lower.includes("confused") || lower.includes("understand")) return "Proverbs 3:5-6";
  if (lower.includes("conflict") || lower.includes("argue")) return "Matthew 18:15";
  return null;
}

// ============================================================
// FEATURE 8: WEIGHT OF WORDS
// ============================================================

export const scoreWeightOfWords = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { text } = request.data as { text: string };

  if (!text || text.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Text is required.");
  }

  // In production: call AI for nuanced scoring
  // Raw text NOT stored or logged
  const { label, value, flags } = scoreTextLocally(text);
  const suggestedRewrite = label === "harmful" || label === "sharp"
    ? generateGracefulRewriteLocal()
    : null;

  return {
    scoreLabel: label,
    scoreValue: value,
    flags,
    suggestedRewrite
  };
});

function scoreTextLocally(text: string): { label: string; value: number; flags: string[] } {
  const lower = text.toLowerCase();
  let value = 0.3;
  const flags: string[] = [];

  // Positive signals
  if (lower.includes("encourage") || lower.includes("proud of") || lower.includes("appreciate")) {
    value -= 0.15; flags.push("high_encouragement");
  }
  if (lower.includes("humbly") || lower.includes("i think") || lower.includes("in my view")) {
    value -= 0.1;
  }

  // Negative signals
  const shameWords = ["should be ashamed", "how could you", "disappointing", "pathetic", "always fail"];
  if (shameWords.some(w => lower.includes(w))) { value += 0.3; flags.push("shame_language"); }

  const spiritualManip = ["god told me", "if you were really", "true christian", "you have to believe"];
  if (spiritualManip.some(w => lower.includes(w))) { value += 0.35; flags.push("spiritual_manipulation"); }

  const sarcasm = ["oh sure", "right, because", "wow, great", "brilliant idea"];
  if (sarcasm.some(w => lower.includes(w))) { value += 0.15; flags.push("sarcasm_detected"); }

  const condemnation = ["you will answer", "condemned", "judgment is coming", "wicked"];
  if (condemnation.some(w => lower.includes(w))) { value += 0.25; flags.push("condemnation_tone"); }

  const correctionIntensity = ["you are wrong", "completely wrong", "absolutely incorrect"];
  if (correctionIntensity.some(w => lower.includes(w))) { value += 0.15; flags.push("high_correction_intensity"); }

  value = Math.max(0, Math.min(1, value));

  let label: string;
  if (flags.includes("high_encouragement") && value < 0.2) label = "encouraging";
  else if (value < 0.25) label = "light";
  else if (value < 0.5) label = "heavy";
  else if (value < 0.75) label = "sharp";
  else label = "harmful";

  return { label, value, flags };
}

function generateGracefulRewriteLocal(): string {
  // Placeholder — real impl calls AI
  return "Consider sharing what you observed rather than what you concluded about the person. Starting with 'I noticed...' or 'I felt...' can open a door instead of closing one.";
}

export const generateGracefulRewrite = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { text } = request.data as { text: string };

  if (!text) throw new HttpsError("invalid-argument", "Text required.");

  // In production: call Claude/OpenAI with instructions to preserve intent but increase grace
  // Raw text NOT stored
  const rewrite = generateGracefulRewriteLocal();
  return { rewrite };
});

// ============================================================
// FEATURE 9: COMMUNITY DISCERNMENT
// ============================================================

export const aggregateDiscernmentSignals = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { contentId, signalType } = request.data as { contentId: string; signalType: string };

  const validTypes = [
    "clarification_needed", "concern_raised", "community_encouragement",
    "confusion_signal", "berean_analysis_requested", "scripture_shared"
  ];
  if (!validTypes.includes(signalType)) {
    throw new HttpsError("invalid-argument", "Invalid signal type.");
  }

  const aggregateRef = db.collection("contentDiscernmentAggregates").doc(contentId)
    .collection("signals").doc(signalType);

  const snapshot = await aggregateRef.get();

  if (snapshot.exists) {
    await aggregateRef.update({
      aggregateCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } else {
    await aggregateRef.set({
      contentId,
      signalType,
      aggregateCount: 1,
      thresholdMet: false,
      generatedSummary: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days
    });
  }

  // Check if threshold is met (default: 5 signals)
  const updated = (await aggregateRef.get()).data();
  if (updated && updated["aggregateCount"] >= 5 && !updated["thresholdMet"]) {
    await aggregateRef.update({ thresholdMet: true });
  }

  // Track that THIS user submitted this signal (private, not exposed)
  await db.collection("users").doc(uid).collection("discernmentSignalsSent").add({
    contentId,
    signalType,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  return { submitted: true };
});

export const generateCommunityDiscernmentSummary = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { contentId } = request.data as { contentId: string };

  // In production: fetch content, call Berean AI for summary
  // Returns anonymous community-level summary — no individual users identified
  void contentId;

  return {
    summary: "Several community members asked for clarification on this teaching. Consider adding scripture references or context to help readers understand the point better."
  };
});

// ============================================================
// FEATURE 10: ETERNAL WEIGHT
// ============================================================

export const calculateEternalWeight = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { contentId } = request.data as { contentId: string };

  const signalRef = db.collection("users").doc(uid)
    .collection("eternalWeightSignals").doc(contentId);

  try {
    const post = await db.collection("posts").doc(contentId).get();
    if (!post.exists) {
      return { calculated: false };
    }
    const data = post.data()!;

    const supportingSignals: string[] = [];
    let state = "neutral";
    let confidence = 0.4;

    if (data["prayerCount"] && data["prayerCount"] > 2) {
      supportingSignals.push("generated_prayer");
      state = "growing"; confidence += 0.15;
    }
    if (data["scriptureRefs"] && data["scriptureRefs"].length > 0) {
      supportingSignals.push("scripture_aligned");
      confidence += 0.1;
    }
    if (data["savedCount"] && data["savedCount"] > 3) {
      supportingSignals.push("many_saved");
      state = "bearing_fruit"; confidence += 0.2;
    }

    confidence = Math.min(confidence, 0.9);

    await signalRef.set({
      userId: uid,
      contentId,
      state,
      supportingSignals,
      confidenceScore: confidence,
      reflectionPrompt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { calculated: true, state, confidence };
  } catch (error) {
    logger.error("calculateEternalWeight error", error);
    return { calculated: false };
  }
});

export const updateEternalWeightAfterReflection = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { signalId, reflectionOutcome } = request.data as {
    signalId: string;
    reflectionOutcome: string;
  };

  const validOutcomes = ["positive", "neutral", "convicting", "confusing"];
  if (!validOutcomes.includes(reflectionOutcome)) {
    throw new HttpsError("invalid-argument", "Invalid reflection outcome.");
  }

  const stateMap: Record<string, string> = {
    positive: "bearing_fruit",
    neutral: "neutral",
    convicting: "needs_reflection",
    confusing: "misaligned"
  };

  await db.collection("users").doc(uid)
    .collection("eternalWeightSignals").doc(signalId)
    .update({
      state: stateMap[reflectionOutcome],
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

  return { updated: true };
});

export const generateMeaningPrompt = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { contentId } = request.data as { contentId: string };

  const snapshot = await db.collection("users").doc(uid)
    .collection("eternalWeightSignals").doc(contentId).get();

  const state = snapshot.exists ? (snapshot.data()?.["state"] as string) : "neutral";

  const prompts: Record<string, string> = {
    growing: "This content seems to be growing something. What do you hope it produces over time?",
    neutral: "What was your intention when you shared this? Has anything come from it that you didn't expect?",
    misaligned: "Looking back, what would you do differently? What was your heart at the time?",
    needs_reflection: "What does this content reveal about where you were spiritually when you created it?",
    bearing_fruit: "This content has generated encouragement and prayer. What does that mean to you?",
    default: "What did you hope this content would do in someone's life?"
  };

  return { prompt: prompts[state] || prompts["default"] };
});

export const createWalkWithChristPathFromPattern = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const { pattern } = request.data as { pattern: string };

  // Suppress unused variable warning — uid is validated above (auth required)
  void uid;

  // Generate a personalized Walk with Christ path based on detected spiritual pattern
  const paths: Record<string, { name: string; description: string; days: number }> = {
    grace_without_truth: {
      name: "Grace AND Truth",
      description: "A 7-day walk exploring how grace and truth coexist in Jesus.",
      days: 7
    },
    truth_without_grace: {
      name: "The Tenderness of Truth",
      description: "A 7-day walk on how truth spoken in love changes hearts.",
      days: 7
    },
    avoids_forgiveness: {
      name: "The Freedom of Forgiveness",
      description: "A 5-day walk through what forgiveness actually costs and gives.",
      days: 5
    },
    self_justification: {
      name: "The Searching God",
      description: "A 5-day walk with Psalm 139 and self-examination.",
      days: 5
    }
  };

  const path = paths[pattern] || {
    name: "Deeper Roots",
    description: "A 7-day walk exploring the foundations of your faith.",
    days: 7
  };

  return { path };
});
