import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { requireAuth, requireAppCheck, moderateInput, sanitizeText } from "./moderation";
import { classifyFeedDirection, computeExpiresAt } from "./classifyFeedDirection";
import { applyFeedPreferenceWeights } from "./applyFeedPreferenceWeights";
import type { SubmitFeedDirectionInput, FeedIntelligenceSignalDoc, FeedSignalSafety } from "./types";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

async function checkRateLimit(uid: string): Promise<void> {
  const db = admin.firestore();
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

  const [hourCount, dayCount] = await Promise.all([
    db.collection(`users/${uid}/feedIntelligence/signals`)
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(hourAgo))
      .count().get(),
    db.collection(`users/${uid}/feedIntelligence/signals`)
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(dayAgo))
      .count().get(),
  ]);

  if (hourCount.data().count >= 10) {
    throw new HttpsError("resource-exhausted", "You've updated your feed several times recently. Try again later.");
  }
  if (dayCount.data().count >= 40) {
    throw new HttpsError("resource-exhausted", "Daily feed direction limit reached. Try again tomorrow.");
  }
}

export const submitFeedDirection = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" },
  async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);

    const input = request.data as SubmitFeedDirectionInput;
    if (!input?.rawText || typeof input.rawText !== "string") {
      throw new HttpsError("invalid-argument", "rawText is required.");
    }
    if (input.rawText.trim().length < 3) {
      throw new HttpsError("invalid-argument", "Feed direction is too short.");
    }

    await checkRateLimit(uid);

    const sanitized = sanitizeText(input.rawText);
    const modResult = moderateInput(sanitized);

    if (!modResult.approved) {
      if (modResult.selfHarmRisk) {
        return {
          signalId: null,
          interpretedSummary: "Your feed can be shaped to be more supportive.",
          intentType: "safetyConcern",
          topicsIncreased: ["prayer", "support", "community"],
          topicsDecreased: [],
          modesActivated: [],
          affectedSurfaces: input.affectedSurfaces ?? ["home"],
          duration: "today",
          intensity: "light",
          safetyNotice: modResult.safetyNotice,
          confirmationTitle: "Feed updated with care",
          confirmationBullets: ["More supportive and uplifting content"],
        };
      }
      throw new HttpsError("failed-precondition", "Request could not be processed.");
    }

    const classification = classifyFeedDirection(sanitized, modResult.echoChamberRisk);
    const expiresAt = computeExpiresAt(
      input.duration,
      input.composerContext?.localHour ?? 12,
      input.composerContext?.timezone ?? "UTC"
    );

    const db = admin.firestore();
    const signalRef = db.collection(`users/${uid}/feedIntelligence/signals`).doc();
    const signalId = signalRef.id;

    const safety: FeedSignalSafety = {
      moderationStatus: modResult.manipulationRisk ? "flagged" : "clean",
      safetyNotice: modResult.safetyNotice,
      echoChamberRisk: modResult.echoChamberRisk,
      selfHarmRisk: modResult.selfHarmRisk,
      manipulationRisk: modResult.manipulationRisk,
    };

    const signalDoc: FeedIntelligenceSignalDoc = {
      signalId,
      uid,
      rawText: input.rawText.slice(0, 800),
      sanitizedText: sanitized,
      interpretedSummary: classification.interpretedSummary,
      intentType: classification.intentType,
      confidence: classification.confidence,
      topicsIncreased: classification.topicsIncreased,
      topicsDecreased: classification.topicsDecreased,
      modesActivated: classification.modesActivated,
      duration: input.duration,
      intensity: input.intensity,
      affectedSurfaces: input.affectedSurfaces ?? ["home", "media"],
      visibility: input.visibility,
      source: "composer",
      status: "active",
      safety,
      expiresAt: expiresAt ? admin.firestore.Timestamp.fromDate(expiresAt) : null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await Promise.all([
      signalRef.set(signalDoc),
      applyFeedPreferenceWeights(
        uid,
        classification,
        input.duration,
        input.intensity,
        input.affectedSurfaces ?? ["home", "media"]
      ),
    ]);

    const confirmationBullets: string[] = [];
    if (classification.topicsIncreased.length > 0) {
      confirmationBullets.push(`More: ${classification.topicsIncreased.slice(0, 3).join(", ")}`);
    }
    if (classification.topicsDecreased.length > 0) {
      confirmationBullets.push(`Less: ${classification.topicsDecreased.slice(0, 3).join(", ")}`);
    }
    if (modResult.echoChamberRisk) {
      confirmationBullets.push("Healthy diversity preserved");
    }

    return {
      signalId,
      interpretedSummary: classification.interpretedSummary,
      intentType: classification.intentType,
      topicsIncreased: classification.topicsIncreased,
      topicsDecreased: classification.topicsDecreased,
      modesActivated: classification.modesActivated,
      affectedSurfaces: input.affectedSurfaces ?? ["home", "media"],
      duration: input.duration,
      intensity: input.intensity,
      safetyNotice: modResult.safetyNotice ?? null,
      confirmationTitle: "Feed updated",
      confirmationBullets,
    };
  }
);
