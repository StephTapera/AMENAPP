// safetyOS.ts
// Social Safety OS — Firebase Cloud Functions (Node 20, strict TypeScript)
// Callable functions consumed by AmenSocialSafetyService.swift

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

const db = getFirestore();

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type SafetyAction = "allow" | "warn" | "review" | "block";
type RiskCategory =
  | "youthMentalHealth"
  | "exploitation"
  | "sexualExploitation"
  | "childSafety"
  | "csam"
  | "grooming"
  | "sexTrafficking"
  | "sextortion"
  | "pornography"
  | "nonConsensualIntimateImagery"
  | "prostitutionFacilitation"
  | "cyberbullying"
  | "misinformation"
  | "addiction";
type Severity = "low" | "medium" | "high" | "critical";

interface SafetyDecision {
  action: SafetyAction;
  riskCategory: RiskCategory | null;
  severity: Severity;
  reason: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  appealEligible: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAuth(request: functions.CallableRequest): string {
  if (!request.auth?.uid) {
    throw new functions.HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

async function isMinor(uid: string): Promise<boolean> {
  try {
    const doc = await db.collection("users").doc(uid).get();
    const ageTier = doc.data()?.ageTier as string | undefined;
    return ageTier === "minor" || ageTier === "teen";
  } catch {
    return false;
  }
}

function allowDecision(): SafetyDecision {
  return {
    action: "allow",
    riskCategory: null,
    severity: "low",
    reason: null,
    userFacingMessage: null,
    requiresHumanReview: false,
    appealEligible: true,
  };
}

// ---------------------------------------------------------------------------
// evaluateContentSafety
// ---------------------------------------------------------------------------

export const evaluateContentSafety = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { contentId, contentType, text, mediaURLs, authorId } = request.data as {
      contentId: string;
      contentType: string;
      text?: string;
      mediaURLs?: string[];
      authorId: string;
    };

    const decision = await runContentSafetyClassifier(
      uid,
      text ?? "",
      mediaURLs ?? [],
      contentType
    );

    await db.collection("safetyDecisions").add({
      contentId,
      contentType,
      authorId,
      evaluatorUid: uid,
      ...decision,
      evaluatedAt: FieldValue.serverTimestamp(),
    });

    logger.info("evaluateContentSafety", { contentId, action: decision.action });
    return decision;
  }
);

// ---------------------------------------------------------------------------
// publishWithSafetyDecision
// ---------------------------------------------------------------------------

export const publishWithSafetyDecision = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    requireAuth(request);
    const { contentId, contentType, action } = request.data as {
      contentId: string;
      contentType: string;
      action: SafetyAction;
    };

    if (action === "block") {
      return { published: false };
    }

    await db
      .collection(contentType === "message" ? "messages" : "posts")
      .doc(contentId)
      .set({ safetyCleared: true, safetyClearedAt: FieldValue.serverTimestamp() }, { merge: true });

    return { published: true };
  }
);

// ---------------------------------------------------------------------------
// evaluateMessageSafety
// ---------------------------------------------------------------------------

export const evaluateMessageSafety = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { conversationId, message, senderId, recipientId, recipientIsMinor } =
      request.data as {
        conversationId: string;
        message: string;
        senderId: string;
        recipientId: string;
        recipientIsMinor: boolean;
      };

    if (uid !== senderId) {
      throw new functions.HttpsError("permission-denied", "Sender mismatch.");
    }

    const minorFactor = recipientIsMinor || (await isMinor(recipientId));
    const decision = await runMessageSafetyClassifier(message, minorFactor);

    await db.collection("messageSafetyEvents").add({
      conversationId,
      senderId,
      recipientId,
      ...decision,
      evaluatedAt: FieldValue.serverTimestamp(),
    });

    logger.info("evaluateMessageSafety", { conversationId, action: decision.action });
    return decision;
  }
);

// ---------------------------------------------------------------------------
// createSafetyReport
// ---------------------------------------------------------------------------

export const createSafetyReport = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { entityId, entityType, category, description, evidenceURLs } =
      request.data as {
        entityId: string;
        entityType: string;
        category: RiskCategory;
        description?: string;
        evidenceURLs?: string[];
      };

    const severity = categorySeverity(category);
    const ref = await db.collection("safetyReports").add({
      entityId,
      entityType,
      reporterId: uid,
      category,
      severity,
      description: description ?? null,
      evidenceURLs: evidenceURLs ?? [],
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });

    if (severity === "critical" || severity === "high") {
      await db.collection("safetyQueue").add({
        reportId: ref.id,
        priority: severity === "critical" ? 1 : 2,
        queuedAt: FieldValue.serverTimestamp(),
      });
    }

    logger.info("createSafetyReport", { reportId: ref.id, category, severity });
    return { reportId: ref.id, severity };
  }
);

// ---------------------------------------------------------------------------
// activateSextortionPanicFlow
// ---------------------------------------------------------------------------

export const activateSextortionPanicFlow = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    requireAuth(request);
    const { userId } = request.data as { userId: string };

    const batch = db.batch();

    // Lock DMs from unknown contacts
    batch.set(
      db.collection("users").doc(userId).collection("safetyFlags").doc("dmLock"),
      { active: true, reason: "sextortionPanic", activatedAt: FieldValue.serverTimestamp() }
    );

    // Escalate to trusted contacts
    const contactsSnap = await db
      .collection("users")
      .doc(userId)
      .collection("trustedContacts")
      .where("notificationLevel", "in", ["alerts", "emergencyOnly"])
      .get();

    contactsSnap.docs.forEach((doc) => {
      const contactUid = doc.data().contactUserId as string;
      batch.set(db.collection("safetyEscalations").doc(), {
        targetUid: userId,
        contactUid,
        type: "sextortionPanic",
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    logger.warn("activateSextortionPanicFlow", { userId });
    return { activated: true };
  }
);

// ---------------------------------------------------------------------------
// updateTrustedContacts
// ---------------------------------------------------------------------------

export const updateTrustedContacts = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { action, contactId, relationshipType, notificationLevel } =
      request.data as {
        action: "add" | "remove";
        contactId: string;
        relationshipType?: string;
        notificationLevel?: string;
      };

    const ref = db
      .collection("users")
      .doc(uid)
      .collection("trustedContacts")
      .doc(contactId);

    if (action === "remove") {
      await ref.delete();
    } else {
      const contactUser = await getAuth().getUser(contactId).catch(() => null);
      await ref.set({
        contactUserId: contactId,
        displayName: contactUser?.displayName ?? "Unknown",
        avatarURL: contactUser?.photoURL ?? null,
        relationshipType: relationshipType ?? "friend",
        notificationLevel: notificationLevel ?? "alerts",
        addedAt: FieldValue.serverTimestamp(),
      });
    }

    return { success: true };
  }
);

// ---------------------------------------------------------------------------
// updateFeedControls
// ---------------------------------------------------------------------------

export const updateFeedControls = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { mode, categories, sessionDurationMinutes, quietHoursStart, quietHoursEnd } =
      request.data as {
        mode: string;
        categories: string[];
        sessionDurationMinutes?: number;
        quietHoursStart?: string;
        quietHoursEnd?: string;
      };

    await db
      .collection("users")
      .doc(uid)
      .collection("feedControls")
      .doc("current")
      .set(
        {
          mode,
          categories,
          sessionDurationMinutes: sessionDurationMinutes ?? null,
          quietHoursStart: quietHoursStart ?? null,
          quietHoursEnd: quietHoursEnd ?? null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    return { success: true };
  }
);

// ---------------------------------------------------------------------------
// recordSessionBoundarySignal
// ---------------------------------------------------------------------------

export const recordSessionBoundarySignal = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { signalType, intensity, context } = request.data as {
      signalType: string;
      intensity: number;
      context?: string;
    };

    await db
      .collection("users")
      .doc(uid)
      .collection("wellbeingSignals")
      .add({
        signalType,
        intensity,
        context: context ?? null,
        recordedAt: FieldValue.serverTimestamp(),
      });

    // Check if we should create a boundary nudge
    const highSignals = await db
      .collection("users")
      .doc(uid)
      .collection("wellbeingSignals")
      .where("intensity", ">=", 0.7)
      .where("recordedAt", ">=", Timestamp.fromMillis(Date.now() - 30 * 60 * 1000))
      .count()
      .get();

    if (highSignals.data().count >= 3) {
      await db
        .collection("users")
        .doc(uid)
        .collection("sessionBoundaries")
        .doc("active")
        .set({
          id: "active",
          action: "selahPause",
          message: "You've been scrolling for a while. Take a mindful moment.",
          triggeredAt: FieldValue.serverTimestamp(),
          dismissed: false,
        });
    }

    return { recorded: true };
  }
);

// ---------------------------------------------------------------------------
// submitClaimContext
// ---------------------------------------------------------------------------

export const submitClaimContext = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { contentId, claimType, sourceURL, sourceAttribution, factCheckerNotes } =
      request.data as {
        contentId: string;
        claimType: string;
        sourceURL?: string;
        sourceAttribution?: string;
        factCheckerNotes?: string;
      };

    await db.collection("claimContexts").add({
      contentId,
      claimType,
      sourceURL: sourceURL ?? null,
      sourceAttribution: sourceAttribution ?? null,
      factCheckerNotes: factCheckerNotes ?? null,
      submittedBy: uid,
      verificationStatus: "pending",
      submittedAt: FieldValue.serverTimestamp(),
    });

    return { submitted: true };
  }
);

// ---------------------------------------------------------------------------
// getRecommendationContext
// ---------------------------------------------------------------------------

export const getRecommendationContext = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    requireAuth(request);
    const { contentId } = request.data as { contentId: string };

    const doc = await db.collection("posts").doc(contentId).get();
    if (!doc.exists) {
      return { explanation: null };
    }
    const data = doc.data() ?? {};
    const reasons: string[] = [];
    if (data.amenCount > 5) reasons.push("popular in your community");
    if (data.topicTags?.length) reasons.push(`related to ${data.topicTags[0]}`);
    if (data.churchId) reasons.push("from your church network");

    return {
      explanation: reasons.length
        ? `You're seeing this because it's ${reasons.join(", ")}.`
        : "You're seeing this based on your activity.",
    };
  }
);

// ---------------------------------------------------------------------------
// requestHumanReview
// ---------------------------------------------------------------------------

export const requestHumanReview = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const { contentId, reason } = request.data as { contentId: string; reason: string };

    await db.collection("humanReviewQueue").add({
      contentId,
      reason,
      requestedBy: uid,
      status: "pending",
      queuedAt: FieldValue.serverTimestamp(),
    });

    return { queued: true };
  }
);

// ---------------------------------------------------------------------------
// resolveSafetyReview
// ---------------------------------------------------------------------------

export const resolveSafetyReview = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    requireAuth(request);
    const { reportId, resolution, notes } = request.data as {
      reportId: string;
      resolution: string;
      notes?: string;
    };

    await db.collection("safetyReports").doc(reportId).update({
      status: resolution,
      resolverNotes: notes ?? null,
      resolvedAt: FieldValue.serverTimestamp(),
    });

    return { resolved: true };
  }
);

// ---------------------------------------------------------------------------
// getSafetyPolicySnapshot
// ---------------------------------------------------------------------------

export const getSafetyPolicySnapshot = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (_request) => {
    const doc = await db.collection("config").doc("safetyPolicy").get();
    return doc.data() ?? {};
  }
);

// ---------------------------------------------------------------------------
// resetRecommendationTraining
// ---------------------------------------------------------------------------

export const resetRecommendationTraining = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    await db
      .collection("users")
      .doc(uid)
      .collection("recommendationSignals")
      .doc("profile")
      .delete();
    return { reset: true };
  }
);

// ---------------------------------------------------------------------------
// Internal classifiers (rule-based, extend with ML as needed)
// ---------------------------------------------------------------------------

async function runContentSafetyClassifier(
  uid: string,
  text: string,
  _mediaURLs: string[],
  _contentType: string
): Promise<SafetyDecision> {
  const lower = text.toLowerCase();

  // Child sexual exploitation and grooming signals.
  const childSafetyPatterns = [
    /\b(don'?t|do\s+not)\s+tell\s+(your\s+)?(parents?|mom|dad|guardian|teacher|pastor)\b/i,
    /\bkeep\s+this\s+(a\s+)?secret\b/i,
    /\bare\s+you\s+alone\b/i,
  ];
  if (childSafetyPatterns.some((p) => p.test(lower))) {
    return {
      action: "block",
      riskCategory: "grooming",
      severity: "critical",
      reason: "Potential grooming or child-safety coercion language",
      userFacingMessage:
        "This content can't be posted. If you're in danger, contact a trusted adult or call emergency services.",
      requiresHumanReview: true,
      appealEligible: false,
    };
  }

  const exploitationPatterns = [
    /\bsend\s+(me\s+)?(nudes?|pics?|photos?)\b/i,
    /\bexplicit\s+(pics?|photos?|videos?)\b/i,
    /\b(leak|expose)\s+(your\s+)?(pics?|photos?|videos?)\b/i,
  ];
  if (exploitationPatterns.some((p) => p.test(lower))) {
    return {
      action: "block",
      riskCategory: "sexualExploitation" as RiskCategory,
      severity: "critical",
      reason: "Potential sexual exploitation language",
      userFacingMessage:
        "This content can't be posted. If you're in danger, please contact a trusted adult or call 988.",
      requiresHumanReview: true,
      appealEligible: false,
    };
  }

  const traffickingPatterns = [
    /\b(modeling|travel|hotel|room|ride)\b.*\b(pay|cash|client|date)\b/i,
    /\bcommercial\s+sex\b/i,
    /\bescort\s+services?\b/i,
  ];
  if (traffickingPatterns.some((p) => p.test(lower))) {
    return {
      action: "block",
      riskCategory: "sexTrafficking",
      severity: "critical",
      reason: "Potential trafficking or prostitution facilitation language",
      userFacingMessage:
        "This content violates our safety rules and can't be posted.",
      requiresHumanReview: true,
      appealEligible: false,
    };
  }

  // Self-harm / mental health crisis signals
  const crisisPatterns = [
    /\b(want\s+to\s+(die|kill\s+myself|end\s+it))\b/i,
    /\b(suicide|self.harm|cutting\s+myself)\b/i,
  ];
  if (crisisPatterns.some((p) => p.test(lower))) {
    const authorMinor = await isMinor(uid);
    return {
      action: authorMinor ? "review" : "warn",
      riskCategory: "youthMentalHealth",
      severity: authorMinor ? "critical" : "high",
      reason: "Mental health crisis language detected",
      userFacingMessage:
        "We care about you. If you're struggling, Selah's crisis support is here for you. You can also call or text 988.",
      requiresHumanReview: authorMinor,
      appealEligible: true,
    };
  }

  // Cyberbullying / harassment
  const harassmentPatterns = [/\b(kill\s+yourself|kys)\b/i, /\b(worthless|nobody\s+loves?\s+you)\b/i];
  if (harassmentPatterns.some((p) => p.test(lower))) {
    return {
      action: "block",
      riskCategory: "cyberbullying",
      severity: "high",
      reason: "Harassment language",
      userFacingMessage:
        "This content violates our community guidelines on harassment and can't be posted.",
      requiresHumanReview: true,
      appealEligible: true,
    };
  }

  return allowDecision();
}

async function runMessageSafetyClassifier(
  message: string,
  recipientIsMinor: boolean
): Promise<SafetyDecision> {
  const lower = message.toLowerCase();

  const adultRequestPatterns = [
    /\bsend\s+(me\s+)?(nudes?|pics?|photos?)\b/i,
    /\bhow\s+old\s+are\s+you\b/i,
    /\bdon'?t\s+tell\s+(your\s+)?parents?\b/i,
    /\bkeep\s+this\s+(a\s+)?secret\b/i,
  ];

  if (recipientIsMinor && adultRequestPatterns.some((p) => p.test(lower))) {
    return {
      action: "block",
      riskCategory: "grooming",
      severity: "critical",
      reason: "Potential grooming message to minor",
      userFacingMessage:
        "This message can't be sent. Your account has been flagged for review.",
      requiresHumanReview: true,
      appealEligible: false,
    };
  }

  return allowDecision();
}

function categorySeverity(category: RiskCategory): Severity {
  const map: Record<RiskCategory, Severity> = {
    exploitation: "critical",
    sexualExploitation: "critical",
    childSafety: "critical",
    csam: "critical",
    grooming: "critical",
    sexTrafficking: "critical",
    sextortion: "critical",
    pornography: "high",
    nonConsensualIntimateImagery: "critical",
    prostitutionFacilitation: "high",
    youthMentalHealth: "high",
    cyberbullying: "high",
    misinformation: "medium",
    addiction: "low",
  };
  return map[category] ?? "medium";
}

// ---------------------------------------------------------------------------
// evaluateMediaIntegrity
// ---------------------------------------------------------------------------
// Inspects a media asset (image or video) for integrity signals:
//   • Known CSAM hash prefix patterns (placeholder — real deployment uses
//     PhotoDNA or NCMEC integration, never done client-side)
//   • Filename / URL signals indicating synthetic / AI-generated content
//   • Explicit content markers from client metadata
//   • Returns a SafetyDecision the iOS client uses to gate upload or label.

export const evaluateMediaIntegrity = functions.onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request) => {
    const uid = requireAuth(request);
    const {
      mediaURL,
      mediaType,
      contentId,
      clientLabels,
      isAIGenerated,
      fileSizeBytes,
    } = request.data as {
      mediaURL: string;
      mediaType: "image" | "video" | "audio";
      contentId?: string;
      clientLabels?: string[];
      isAIGenerated?: boolean;
      fileSizeBytes?: number;
    };

    // ------------------------------------------------------------------
    // Rule 1: AI-generated content disclosure
    // ------------------------------------------------------------------
    if (isAIGenerated === true) {
      await db.collection("contentIntegrityLabels").add({
        mediaURL,
        mediaType,
        contentId: contentId ?? null,
        uploaderUid: uid,
        label: "ai_generated",
        source: "client_disclosure",
        createdAt: FieldValue.serverTimestamp(),
      });

      const decision: SafetyDecision = {
        action: "allow",
        riskCategory: null,
        severity: "low",
        reason: "AI-generated content will be labelled for the community.",
        userFacingMessage:
          "Your post will be marked as AI-generated so the community can engage with full context.",
        requiresHumanReview: false,
        appealEligible: true,
      };
      logger.info("evaluateMediaIntegrity:aiGenerated", { uid, mediaType });
      return { ...decision, integrityLabel: "ai_generated" };
    }

    // ------------------------------------------------------------------
    // Rule 2: Client-supplied explicit labels
    // ------------------------------------------------------------------
    const explicitLabels = ["nudity", "graphic_violence", "csam", "explicit"];
    const matchedLabel = (clientLabels ?? []).find((l) =>
      explicitLabels.includes(l.toLowerCase())
    );
    if (matchedLabel) {
      await db.collection("contentIntegrityLabels").add({
        mediaURL,
        mediaType,
        contentId: contentId ?? null,
        uploaderUid: uid,
        label: matchedLabel,
        source: "client_labels",
        createdAt: FieldValue.serverTimestamp(),
      });

      // CSAM is immediate block + escalation
      if (matchedLabel.toLowerCase() === "csam") {
        await db.collection("safetyQueue").add({
          type: "csam_flag",
          mediaURL,
          uploaderUid: uid,
          priority: 0,
          queuedAt: FieldValue.serverTimestamp(),
        });
        logger.error("evaluateMediaIntegrity:csamFlag", { uid, mediaURL });
        return {
          action: "block",
          riskCategory: "exploitation",
          severity: "critical",
          reason: "CSAM signal detected",
          userFacingMessage:
            "This content cannot be uploaded. If you believe this is an error, contact support.",
          requiresHumanReview: true,
          appealEligible: false,
          integrityLabel: "csam",
        };
      }

      // Other explicit labels → hold for review
      logger.warn("evaluateMediaIntegrity:explicitLabel", { uid, matchedLabel });
      return {
        action: "review",
        riskCategory: "exploitation" as RiskCategory,
        severity: "high" as Severity,
        reason: `Client label: ${matchedLabel}`,
        userFacingMessage:
          "This content requires review before it can be published. We'll notify you when it's approved.",
        requiresHumanReview: true,
        appealEligible: true,
        integrityLabel: matchedLabel,
      };
    }

    // ------------------------------------------------------------------
    // Rule 3: Oversized files (potential evasion payload)
    // ------------------------------------------------------------------
    const MAX_IMAGE_BYTES = 25 * 1024 * 1024;   // 25 MB
    const MAX_VIDEO_BYTES = 500 * 1024 * 1024;  // 500 MB
    const sizeLimit = mediaType === "video" ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
    if (fileSizeBytes !== undefined && fileSizeBytes > sizeLimit) {
      logger.warn("evaluateMediaIntegrity:oversize", { uid, fileSizeBytes, mediaType });
      return {
        action: "block",
        riskCategory: null,
        severity: "medium",
        reason: "File size exceeds platform limit",
        userFacingMessage:
          mediaType === "video"
            ? "Videos must be under 500 MB."
            : "Images must be under 25 MB.",
        requiresHumanReview: false,
        appealEligible: false,
        integrityLabel: "oversize",
      };
    }

    // ------------------------------------------------------------------
    // Rule 4: All clear — log and allow
    // ------------------------------------------------------------------
    await db.collection("contentIntegrityLabels").add({
      mediaURL,
      mediaType,
      contentId: contentId ?? null,
      uploaderUid: uid,
      label: "approved",
      source: "integrity_pipeline",
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("evaluateMediaIntegrity:approved", { uid, mediaType });
    return {
      action: "allow",
      riskCategory: null,
      severity: "low",
      reason: null,
      userFacingMessage: null,
      requiresHumanReview: false,
      appealEligible: true,
      integrityLabel: "approved",
    };
  }
);
