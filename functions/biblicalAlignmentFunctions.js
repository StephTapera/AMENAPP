const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {
  applyDefaultLimit,
} = require("./rateLimiter");
const {
  getDiscernmentPrompt: buildDiscernmentPrompt,
  hashContent,
  normalizeText,
  previewContent,
  runBiblicalAlignmentPipeline,
  suggestBiblicalRewrite: buildRewrite,
} = require("./alignmentPipeline");

const REGION = "us-central1";
const db = () => admin.firestore();
const ts = admin.firestore.FieldValue.serverTimestamp;

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return request.auth.uid;
}

function validateString(value, field, max = 4000, required = true) {
  if (value == null || value === "") {
    if (required) {
      throw new HttpsError("invalid-argument", `${field} is required.`);
    }
    return "";
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  return value.slice(0, max);
}

function sanitizeProfile(profile, userId) {
  return {
    userId,
    defaultLens: profile.defaultLens || "balanced_biblical",
    discernmentMode: profile.discernmentMode || "auto",
    scripturePreference: profile.scripturePreference || "only_when_relevant",
    correctionMemoryEnabled: profile.correctionMemoryEnabled !== false,
    weeklySummaryEnabled: profile.weeklySummaryEnabled !== false,
    simpleModeEnabled: profile.simpleModeEnabled === true,
    explicitContentProtectionEnabled: profile.explicitContentProtectionEnabled !== false,
    exploitationProtectionEnabled: profile.exploitationProtectionEnabled !== false,
    preferredTone: profile.preferredTone || "pastoral",
    aggregateStats: profile.aggregateStats || {},
  };
}

async function getUserProfile(userId) {
  const ref = db().collection("user_alignment_profiles").doc(userId);
  const snap = await ref.get();
  if (!snap.exists) {
    const seed = {
      userId,
      defaultLens: "balanced_biblical",
      discernmentMode: "auto",
      scripturePreference: "only_when_relevant",
      correctionMemoryEnabled: true,
      weeklySummaryEnabled: true,
      simpleModeEnabled: false,
      explicitContentProtectionEnabled: true,
      exploitationProtectionEnabled: true,
      preferredTone: "pastoral",
      aggregateStats: {
        totalChecks: 0,
        alignedCount: 0,
        contextNeededCount: 0,
        discernmentCount: 0,
        correctionCount: 0,
        blockedCount: 0,
        humanReviewCount: 0,
        protectionMoments: 0,
      },
      createdAt: ts(),
      updatedAt: ts(),
    };
    await ref.set(seed, {merge: true});
    return seed;
  }
  return snap.data();
}

async function incrementStats(userId, status) {
  const ref = db().collection("user_alignment_profiles").doc(userId);
  const stats = {
    "aggregateStats.totalChecks": admin.firestore.FieldValue.increment(1),
    updatedAt: ts(),
  };
  if (status === "aligned") stats["aggregateStats.alignedCount"] = admin.firestore.FieldValue.increment(1);
  if (status === "context_needed") stats["aggregateStats.contextNeededCount"] = admin.firestore.FieldValue.increment(1);
  if (status === "needs_discernment") stats["aggregateStats.discernmentCount"] = admin.firestore.FieldValue.increment(1);
  if (status === "blocked") {
    stats["aggregateStats.blockedCount"] = admin.firestore.FieldValue.increment(1);
    stats["aggregateStats.protectionMoments"] = admin.firestore.FieldValue.increment(1);
  }
  if (status === "human_review") stats["aggregateStats.humanReviewCount"] = admin.firestore.FieldValue.increment(1);
  await ref.set(stats, {merge: true});
}

exports.checkBiblicalAlignment = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      await applyDefaultLimit(userId, "comment_create");

      const text = validateString(request.data.text, "text", 6000, false);
      const targetType = validateString(request.data.targetType, "targetType", 64);
      const targetId = validateString(request.data.targetId, "targetId", 256, false) || null;
      const sourceSurface = validateString(request.data.sourceSurface, "sourceSurface", 64);
      const requestedLens = validateString(request.data.requestedLens, "requestedLens", 64, false) || undefined;
      const hasMedia = request.data.hasMedia === true;

      const profile = await getUserProfile(userId);
      const result = runBiblicalAlignmentPipeline({
        text,
        targetType,
        targetId,
        sourceSurface,
        requestedLens,
        hasMedia,
        explicitContentProtectionEnabled: profile.explicitContentProtectionEnabled !== false,
        exploitationProtectionEnabled: profile.exploitationProtectionEnabled !== false,
      });

      const checkRef = db().collection("ai_alignment_checks").doc();
      await checkRef.set({
        userId,
        contentOwnerId: userId,
        targetType,
        targetId,
        sourceSurface,
        inputHash: hashContent(text),
        inputPreview: previewContent(text),
        rawTextRef: null,
        status: result.status,
        alignmentScore: result.alignmentScore,
        confidence: result.confidence,
        categories: result.categories,
        flags: result.flags,
        suggestedAction: result.suggestedAction,
        userVisibleSummary: result.userVisibleSummary,
        scriptureSuggestions: result.scriptureSuggestions,
        modelMetadata: {
          provider: "local",
          model: "amen-alignment-v1",
          pipelineVersion: "1",
          promptVersion: "1",
        },
        createdAt: ts(),
        expiresAt: null,
      });

      if (result.status === "human_review" || result.status === "blocked") {
        await db().collection("moderation_review_queue").add({
          targetType,
          targetId,
          userId,
          checkId: checkRef.id,
          priority: result.status === "blocked" ? "high" : "medium",
          reason: result.userVisibleSummary,
          status: "open",
          createdAt: ts(),
          updatedAt: ts(),
        });
      }

      await incrementStats(userId, result.status);

      return {
        checkId: checkRef.id,
        status: result.status,
        alignmentScore: result.alignmentScore,
        confidence: result.confidence,
        suggestedAction: result.suggestedAction,
        userVisibleSummary: result.userVisibleSummary,
        flags: result.flags,
        scriptureSuggestions: result.scriptureSuggestions,
        rewriteSuggestion: result.rewriteSuggestion,
      };
    },
);

exports.suggestBiblicalRewrite = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      await applyDefaultLimit(userId, "comment_create");
      const originalText = validateString(request.data.originalText, "originalText", 6000);
      const lens = validateString(request.data.lens, "lens", 64, false) || "balanced_biblical";
      return buildRewrite({originalText, lens});
    },
);

exports.saveAICorrection = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      await applyDefaultLimit(userId, "comment_create");
      const correctionText = validateString(request.data.correctionText, "correctionText", 4000);
      const selectedLens = validateString(request.data.selectedLens, "selectedLens", 64);
      const correctionRef = db().collection("ai_corrections").doc();
      await correctionRef.set({
        userId,
        originalCheckId: validateString(request.data.originalCheckId, "originalCheckId", 128, false) || null,
        targetType: validateString(request.data.targetType, "targetType", 64),
        targetId: validateString(request.data.targetId, "targetId", 256, false) || null,
        originalTextHash: hashContent(validateString(request.data.originalText, "originalText", 6000, false)),
        correctionText,
        selectedLens,
        correctionIntent: validateString(request.data.correctionIntent, "correctionIntent", 64, false) || "other",
        savedToProfile: request.data.savedToProfile === true,
        createdAt: ts(),
      });

      const profileRef = db().collection("user_alignment_profiles").doc(userId);
      const profile = await getUserProfile(userId);
      const updates = {
        "aggregateStats.correctionCount": admin.firestore.FieldValue.increment(1),
        updatedAt: ts(),
      };
      if (request.data.savedToProfile === true && profile.correctionMemoryEnabled !== false) {
        updates.defaultLens = selectedLens;
      }
      await profileRef.set(updates, {merge: true});

      return {correctionId: correctionRef.id, profileUpdated: request.data.savedToProfile === true};
    },
);

exports.getDiscernmentPrompt = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      const text = validateString(request.data.text, "text", 4000, false);
      const profile = await getUserProfile(userId);
      return buildDiscernmentPrompt({text, surface: request.data.surface}, profile);
    },
);

exports.attachSharedKnowledgeIntegrity = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      const targetType = validateString(request.data.targetType, "targetType", 64);
      const targetId = validateString(request.data.targetId, "targetId", 256);
      const checkId = validateString(request.data.checkId, "checkId", 256);
      const checkSnap = await db().collection("ai_alignment_checks").doc(checkId).get();
      if (!checkSnap.exists) {
        throw new HttpsError("not-found", "Alignment check not found.");
      }
      const check = checkSnap.data();
      if (check.userId !== userId) {
        throw new HttpsError("permission-denied", "You do not own this check.");
      }

      let badge = "none";
      let status = "not_checked";
      if (check.status === "aligned" && check.confidence >= 0.8) {
        badge = "berean_verified";
        status = "berean_verified";
      } else if (check.status === "context_needed") {
        badge = "context_check";
        status = "context_added";
      } else if (check.status === "needs_discernment") {
        badge = "needs_discernment";
        status = "needs_discernment";
      } else if (check.status === "human_review") {
        badge = "held_for_review";
        status = "review_required";
      }

      const ref = db().collection("shared_knowledge_integrity").doc(`${targetType}_${targetId}`);
      await ref.set({
        targetType,
        targetId,
        ownerId: userId,
        status,
        badge,
        isPublic: true,
        userVisibleSummary: check.userVisibleSummary,
        scriptureContext: (check.scriptureSuggestions || []).map((item) => ({
          reference: item.reference,
          reason: item.reason,
        })),
        communitySignals: {
          biblicallySoundVotes: 0,
          needsContextVotes: 0,
          reportCount: 0,
        },
        createdAt: ts(),
        updatedAt: ts(),
      }, {merge: true});

      return {
        integrityId: ref.id,
        badge,
        status,
        userVisibleSummary: check.userVisibleSummary,
      };
    },
);

exports.voteKnowledgeIntegrity = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      await applyDefaultLimit(userId, "report_submit");
      const targetType = validateString(request.data.targetType, "targetType", 64);
      const targetId = validateString(request.data.targetId, "targetId", 256);
      const vote = validateString(request.data.vote, "vote", 64);
      const ref = db().collection("shared_knowledge_integrity").doc(`${targetType}_${targetId}`);
      const voteRef = ref.collection("votes").doc(userId);

      await db().runTransaction(async (tx) => {
        const existing = await tx.get(voteRef);
        if (existing.exists) {
          throw new HttpsError("already-exists", "Vote already recorded.");
        }
        tx.set(voteRef, {vote, userId, createdAt: new Date()});
        tx.set(ref, {
          updatedAt: ts(),
          [`communitySignals.${vote === "biblically_sound" ? "biblicallySoundVotes" : "needsContextVotes"}`]:
            admin.firestore.FieldValue.increment(1),
        }, {merge: true});
      });

      return {success: true};
    },
);

async function computeWeeklySummary(userId, weekStart) {
  const start = weekStart || new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const end = new Date(start.getTime() + 7 * 24 * 60 * 60 * 1000);
  const snapshot = await db().collection("ai_alignment_checks")
      .where("userId", "==", userId)
      .where("createdAt", ">=", start)
      .where("createdAt", "<", end)
      .get();

  const docs = snapshot.docs.map((doc) => doc.data());
  const total = docs.length || 1;
  const aligned = docs.filter((doc) => doc.status === "aligned").length;
  const discernment = docs.filter((doc) => doc.status === "needs_discernment").length;
  const blocked = docs.filter((doc) => doc.status === "blocked" || doc.status === "human_review").length;
  const summary = {
    userId,
    weekStart: start,
    weekEnd: end,
    stats: {
      totalInteractions: docs.length,
      alignedPercent: Math.round((aligned / total) * 100),
      correctionsMade: 0,
      discernmentMoments: discernment,
      contextChecksAdded: docs.filter((doc) => doc.status === "context_needed").length,
      blockedOrHeldItems: blocked,
      spiritualProtectionMoments: docs.filter((doc) => (doc.flags || []).some((flag) =>
        ["pornography_or_explicit_content", "grooming", "trafficking_or_exploitation"].includes(flag))).length,
    },
    insights: [
      aligned ? "Most interactions stayed within a healthy tone." : "A gentler posture may help next week.",
    ],
    suggestedPractices: [
      discernment > 0 ? "Pause before responding when the conversation feels spiritually heated." :
        "Keep using a measured tone and clear context.",
    ],
    topScriptureThemes: ["Wisdom", "Discernment", "Humility"],
    createdAt: new Date(),
  };
  return summary;
}

exports.getWeeklyAlignmentSummary = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      const weekStartRaw = validateString(request.data.weekStart, "weekStart", 40, false);
      const weekStart = weekStartRaw ? new Date(weekStartRaw) : null;
      const summary = await computeWeeklySummary(userId, weekStart);
      await db().collection("ai_engagement_summaries")
          .doc(`${userId}_${summary.weekStart.toISOString().slice(0, 10)}`)
          .set({...summary, createdAt: ts()}, {merge: true});
      return {summary};
    },
);

exports.updateAlignmentProfile = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      const userId = requireAuth(request);
      const ref = db().collection("user_alignment_profiles").doc(userId);
      const updates = {
        updatedAt: ts(),
      };
      const allowed = [
        "defaultLens",
        "discernmentMode",
        "scripturePreference",
        "correctionMemoryEnabled",
        "weeklySummaryEnabled",
        "simpleModeEnabled",
        "explicitContentProtectionEnabled",
        "exploitationProtectionEnabled",
        "preferredTone",
      ];
      for (const key of allowed) {
        if (key in (request.data || {})) {
          updates[key] = request.data[key];
        }
      }
      await ref.set(updates, {merge: true});
      const updated = await getUserProfile(userId);
      return {success: true, profile: sanitizeProfile(updated, userId)};
    },
);

exports.generateWeeklyAlignmentSummary = onSchedule(
    {region: REGION, schedule: "0 8 * * 1", timeZone: "America/Chicago"},
    async () => {
      const users = await db().collection("user_alignment_profiles")
          .where("weeklySummaryEnabled", "==", true)
          .get();
      await Promise.all(users.docs.map(async (doc) => {
        const summary = await computeWeeklySummary(doc.id);
        await db().collection("ai_engagement_summaries")
            .doc(`${doc.id}_${summary.weekStart.toISOString().slice(0, 10)}`)
            .set({...summary, createdAt: ts()}, {merge: true});
      }));
    },
);
