/**
 * guardian.ts — GUARDIAN content moderation for communal channels.
 *
 * Trigger: Firestore onCreate on channels/{channelId}/messages/{messageId}
 *
 * This function ONLY runs on the /messages/ subcollection (communal channels).
 * It must NEVER read or write sacredMessages or keyMaterial subcollections.
 * If the channelClass is ever "sacred" at runtime, the function aborts immediately.
 *
 * Verdict semantics:
 *   allow           → isDelivered=true
 *   allow_with_support → isDelivered=true + supportResourcesAttached=true
 *   block           → isDelivered=false (message silenced; sender sees "not sent")
 *   escalate        → isDelivered=false + written to moderationQueue for human review
 *
 * Fail-open: if the classifier returns an error, the message is delivered (allow).
 * Crisis content always receives support resources — it is never silenced.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { initializeApp, getApps } from "firebase-admin/app";

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();

// ── Types ──────────────────────────────────────────────────────────────────

type GuardianDecision = "allow" | "allow_with_support" | "block" | "escalate";
type GuardianRoute = "none" | "support" | "review" | "legal";

interface GuardianResult {
  decision: GuardianDecision;
  category: string;
  reason: string;
  route: GuardianRoute;
}

// ── GUARDIAN system prompt ─────────────────────────────────────────────────

const GUARDIAN_SYSTEM_PROMPT = `You are GUARDIAN, the content safety layer for AMEN, a faith-based social platform.
Your job is to evaluate a message and return a JSON verdict.

Rules:
1. Messages that are harmful, harassing, or violate community standards → block
2. Messages containing crisis signals (suicidal ideation, self-harm, abuse, severe distress) → allow_with_support
   - Always attach support resources; never silence a cry for help.
   - A lament psalm, grief prayer, or "I feel like dying inside" in a prayer context → allow_with_support, not block.
3. CSAM or any content sexualizing minors → escalate with route "legal"
4. Hate speech, doxxing, or credible threats → escalate with route "review"
5. Everything else → allow

Respond ONLY with valid JSON matching this schema:
{
  "decision": "allow" | "allow_with_support" | "block" | "escalate",
  "category": string,
  "reason": string,
  "route": "none" | "support" | "review" | "legal"
}

Context: faith-based community. Members discuss prayer, scripture, and church life.
Do not over-moderate theological discussion, lament language, or honest struggle shared in faith.`;

// ── GCP metadata server identity token (service-to-service auth) ───────────

async function fetchServiceAccountIdToken(audience: string): Promise<string> {
  const metaUrl =
    `http://metadata.google.internal/computeMetadata/v1/instance/` +
    `service-accounts/default/identity?audience=${encodeURIComponent(audience)}`;
  const resp = await fetch(metaUrl, {
    headers: { "Metadata-Flavor": "Google" },
  });
  if (!resp.ok) {
    throw new Error(`Metadata server ${resp.status}`);
  }
  return resp.text();
}

// ── Call bereanChatProxy callable (existing LLM proxy) ────────────────────

async function classifyWithBerean(
  messageText: string,
  senderId: string,
  channelId: string
): Promise<GuardianResult> {
  const projectId =
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "";
  const region = "us-central1";
  const proxyUrl = `https://${region}-${projectId}.cloudfunctions.net/bereanChatProxy`;

  const idToken = await fetchServiceAccountIdToken(proxyUrl);

  const body = {
    data: {
      mode: "guardian",
      systemPrompt: GUARDIAN_SYSTEM_PROMPT,
      text: messageText,
      senderId,
      channelId,
    },
  };

  const response = await fetch(proxyUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`bereanChatProxy responded ${response.status}`);
  }

  const json = (await response.json()) as { result?: { text?: string } };
  const rawText = json.result?.text ?? "";

  // The model is instructed to return JSON only; extract it defensively
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error("No JSON object found in classifier response");
  }

  const parsed = JSON.parse(jsonMatch[0]) as GuardianResult;

  const validDecisions: GuardianDecision[] = [
    "allow",
    "allow_with_support",
    "block",
    "escalate",
  ];
  if (!validDecisions.includes(parsed.decision)) {
    throw new Error(`Invalid decision value: ${parsed.decision}`);
  }

  return parsed;
}

// ── Firestore trigger ──────────────────────────────────────────────────────

export const guardianModerator = onDocumentCreated(
  "channels/{channelId}/messages/{messageId}",
  async (event) => {
    const { channelId, messageId } = event.params;
    const messageData = event.data?.data();

    if (!messageData) {
      logger.warn("GUARDIAN: missing message data", { channelId, messageId });
      return;
    }

    const messageText: string = messageData.text ?? "";
    const senderId: string = messageData.senderId ?? "";

    // Abort if somehow triggered on a sacred channel (should be impossible
    // because sacredMessages is a separate subcollection, but guard anyway).
    const channelSnap = await db.doc(`channels/${channelId}`).get();
    const channelClass: string = channelSnap.data()?.channelClass ?? "communal";

    if (channelClass === "sacred") {
      logger.error("GUARDIAN: aborting — triggered on sacred channel", {
        channelId,
        messageId,
      });
      return;
    }

    // ── Classify ─────────────────────────────────────────────────────────

    let result: GuardianResult;

    try {
      result = await classifyWithBerean(messageText, senderId, channelId);
    } catch (err) {
      // Fail open: deliver on classifier error; do not block the user
      logger.error("GUARDIAN: classifier error, failing open", {
        channelId,
        messageId,
        err: String(err),
      });
      result = {
        decision: "allow",
        category: "classifier_error",
        reason: "Classifier unavailable; message delivered by fail-open policy.",
        route: "none",
      };
    }

    // ── Apply verdict ─────────────────────────────────────────────────────

    const messageRef = db.doc(`channels/${channelId}/messages/${messageId}`);
    const channelRef = db.doc(`channels/${channelId}`);
    const batch = db.batch();

    switch (result.decision) {
      case "allow":
        batch.update(messageRef, {
          isDelivered: true,
          guardianDecision: "allow",
        });
        break;

      case "allow_with_support":
        batch.update(messageRef, {
          isDelivered: true,
          guardianDecision: "allow_with_support",
          supportResourcesAttached: true,
        });
        break;

      case "block":
        batch.update(messageRef, {
          isDelivered: false,
          guardianDecision: "block",
        });
        break;

      case "escalate": {
        batch.update(messageRef, {
          isDelivered: false,
          guardianDecision: "escalate",
        });

        // Write to moderation queue — admin SDK only collection (client rules deny all)
        const queueRef = db.collection("moderationQueue").doc();
        batch.set(queueRef, {
          channelId,
          messageId,
          senderId,
          messageText,
          guardianCategory: result.category,
          guardianReason: result.reason,
          guardianRoute: result.route,
          createdAt: FieldValue.serverTimestamp(),
          status: "pending",
        });
        break;
      }
    }

    // Update channel preview for delivered messages only
    if (
      result.decision === "allow" ||
      result.decision === "allow_with_support"
    ) {
      const preview =
        messageText.length > 60
          ? `${messageText.substring(0, 57)}...`
          : messageText;
      batch.update(channelRef, {
        lastMessagePreview: preview,
        lastMessageAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    logger.info("GUARDIAN: verdict applied", {
      channelId,
      messageId,
      decision: result.decision,
      category: result.category,
      route: result.route,
    });
  }
);
