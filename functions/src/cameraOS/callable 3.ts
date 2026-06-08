// callable.ts — Camera OS callable Cloud Functions
// interpretContextLens, bereanVisionScan, scanMediaForSafety, reportCSAMFlag

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

// ── Constants ─────────────────────────────────────────────────────────────────

const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_IMAGE_BASE64_BYTES = 4 * 1024 * 1024; // 4 MB base64 limit

// ── Types ─────────────────────────────────────────────────────────────────────

interface InterpretContextLensRequest {
  rawText: string;
  sceneHint: string;
}

interface BereanVisionScanRequest {
  text: string;
}

interface ScanMediaForSafetyRequest {
  imageBase64: string;
  mimeType: string;
  safetyProfile: string;
}

interface ReportCSAMFlagRequest {
  reportId: string;
  captureHash: string;
  reporterUid: string;
}

// ── Rate-limit helper ─────────────────────────────────────────────────────────

/**
 * Enforces a per-user rate limit of maxCalls calls per windowMs milliseconds.
 * Uses a rolling counter stored in Firestore under `cameraOS/rateLimits/<bucket>/<uid>`.
 * Throws HttpsError("resource-exhausted") when the limit is exceeded.
 */
async function enforceRateLimit(
  uid: string,
  bucket: string,
  maxCalls: number,
  windowMs: number
): Promise<void> {
  const ref = db
    .collection("cameraOS")
    .doc("rateLimits")
    .collection(bucket)
    .doc(uid);

  const snap = await ref.get();
  const now = Date.now();

  if (snap.exists) {
    const data = snap.data()!;
    const windowStart: number = data.windowStart ?? 0;
    const count: number = data.count ?? 0;

    if (now - windowStart < windowMs) {
      if (count >= maxCalls) {
        throw new functions.HttpsError(
          "resource-exhausted",
          `Rate limit: max ${maxCalls} calls per ${windowMs / 60000} minute(s).`
        );
      }
      // Still within window — increment counter
      await ref.set({ windowStart, count: count + 1 }, { merge: true });
      return;
    }
  }

  // New window — reset
  await ref.set({ windowStart: now, count: 1 }, { merge: true });
}

// ── Gemini text helper ────────────────────────────────────────────────────────

interface GeminiTextResponse {
  text: string;
  tokenCount: number;
  isMock: boolean;
}

async function callGeminiText(
  systemInstruction: string,
  userPrompt: string,
  temperature: number,
  maxOutputTokens: number
): Promise<GeminiTextResponse> {
  const key = process.env.BEREAN_LLM_KEY ?? "";

  if (!key) {
    logger.info("cameraOS/callGeminiText: BEREAN_LLM_KEY not set — returning mock.");
    return { text: "", tokenCount: 0, isMock: true };
  }

  const url = `${GEMINI_API_BASE}/gemini-1.5-flash:generateContent?key=${key}`;

  const body = {
    system_instruction: {
      parts: [{ text: systemInstruction }],
    },
    contents: [{ parts: [{ text: userPrompt }] }],
    generationConfig: {
      temperature,
      maxOutputTokens,
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    logger.warn(`cameraOS/callGeminiText: HTTP ${response.status} from Gemini.`);
    return { text: "", tokenCount: 0, isMock: true };
  }

  const json = (await response.json()) as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string }> };
    }>;
    usageMetadata?: { totalTokenCount?: number };
  };

  const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const tokenCount = json?.usageMetadata?.totalTokenCount ?? 0;

  return { text: rawText, tokenCount, isMock: false };
}

// ── Gemini vision helper ──────────────────────────────────────────────────────

async function callGeminiVision(
  systemInstruction: string,
  imageBase64: string,
  mimeType: string,
  textPrompt: string,
  maxOutputTokens: number
): Promise<GeminiTextResponse> {
  const key = process.env.BEREAN_LLM_KEY ?? "";

  if (!key) {
    logger.info("cameraOS/callGeminiVision: BEREAN_LLM_KEY not set — returning mock.");
    return { text: "", tokenCount: 0, isMock: true };
  }

  const url = `${GEMINI_API_BASE}/gemini-1.5-flash:generateContent?key=${key}`;

  const body = {
    system_instruction: {
      parts: [{ text: systemInstruction }],
    },
    contents: [
      {
        parts: [
          {
            inline_data: {
              mime_type: mimeType,
              data: imageBase64,
            },
          },
          { text: textPrompt },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens,
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    logger.warn(`cameraOS/callGeminiVision: HTTP ${response.status} from Gemini.`);
    return { text: "", tokenCount: 0, isMock: true };
  }

  const json = (await response.json()) as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string }> };
    }>;
    usageMetadata?: { totalTokenCount?: number };
  };

  const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const tokenCount = json?.usageMetadata?.totalTokenCount ?? 0;

  return { text: rawText, tokenCount, isMock: false };
}

// ── JSON-from-LLM parser ──────────────────────────────────────────────────────

function parseJsonFromLLM<T>(raw: string): T | null {
  const cleaned = raw
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();
  try {
    return JSON.parse(cleaned) as T;
  } catch {
    return null;
  }
}

// ── interpretContextLens ──────────────────────────────────────────────────────

export const interpretContextLens = functions.onCall(
  { enforceAppCheck: true, timeoutSeconds: 60 },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as InterpretContextLensRequest;
    const rawText = String(data?.rawText ?? "").trim();
    const sceneHint = String(data?.sceneHint ?? "").trim();

    if (!rawText) throw new functions.HttpsError("invalid-argument", "rawText is required.");
    if (rawText.length > 5000) {
      throw new functions.HttpsError("invalid-argument", "rawText must be 5000 characters or fewer.");
    }

    // ── Rate limit: 10 calls per minute per user ──────────────────────────────
    try {
      await enforceRateLimit(userId, "interpretContextLens", 10, 60_000);
    } catch (err) {
      if (err instanceof functions.HttpsError) throw err;
      throw new functions.HttpsError("internal", "Rate limit check failed.");
    }

    // ── Build prompt ──────────────────────────────────────────────────────────
    const systemInstruction =
      "You are a content understanding assistant. Given raw OCR text from a camera capture, " +
      "identify the content type and return structured information. Always respond with valid JSON only, no markdown fences.";

    const userPrompt = `Scene hint: ${sceneHint || "none"}

Raw OCR text:
${rawText}

Identify the content type from: meeting_summary, recipe, book_notes, bulletin_events, sermon_notes, generic.

Return JSON in one of these exact shapes:
- Sermon: { "type": "sermon_notes", "payload": { "title": string, "scripture": string[], "summary": string, "discussionQuestions": string[] } }
- Meeting: { "type": "meeting_summary", "payload": { "title": string, "keyPoints": string[], "actionItems": string[] } }
- Recipe: { "type": "recipe", "payload": { "ingredients": string[] } }
- Book notes: { "type": "book_notes", "payload": { "title": string, "keyInsights": string[], "quotes": string[] } }
- Bulletin events: { "type": "bulletin_events", "payload": { "events": Array<{ title: string, date: string, description: string }> } }
- Generic: { "type": "generic", "payload": { "text": string, "summary": string } }`;

    logger.info(`interpretContextLens: processing for uid=${userId}, sceneHint=${sceneHint || "none"}`);

    let result: { type: string; payload: object };

    try {
      const { text, isMock } = await callGeminiText(systemInstruction, userPrompt, 0.3, 1024);

      if (isMock || !text) {
        result = { type: "generic", payload: { text: rawText, summary: "Could not interpret content." } };
      } else {
        const parsed = parseJsonFromLLM<{ type: string; payload: object }>(text);
        if (!parsed || typeof parsed.type !== "string" || typeof parsed.payload !== "object") {
          logger.warn("interpretContextLens: LLM returned unexpected shape — falling back to generic.");
          result = { type: "generic", payload: { text: rawText, summary: "Content parsed with low confidence." } };
        } else {
          result = { type: parsed.type, payload: parsed.payload };
        }
      }
    } catch (err) {
      logger.error("interpretContextLens: unexpected error.", { err: String(err) });
      throw new functions.HttpsError("internal", String(err));
    }

    logger.info(`interpretContextLens: completed for uid=${userId}, type=${result.type}`);
    return result;
  }
);

// ── bereanVisionScan ──────────────────────────────────────────────────────────

interface BereanVisionScanResult {
  scriptureRefs: string[];
  summary: string;
  studyNotes: string[];
  discussionQuestions: string[];
  confidence: number;
  isMock: boolean;
}

const BEREAN_VISION_MOCK: BereanVisionScanResult = {
  scriptureRefs: [],
  summary: "No scripture analysis available — Berean AI key not configured.",
  studyNotes: [],
  discussionQuestions: [],
  confidence: 0,
  isMock: true,
};

export const bereanVisionScan = functions.onCall(
  { enforceAppCheck: true, timeoutSeconds: 60 },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as BereanVisionScanRequest;
    const text = String(data?.text ?? "").trim();

    if (!text) throw new functions.HttpsError("invalid-argument", "text is required.");
    if (text.length > 8000) {
      throw new functions.HttpsError("invalid-argument", "text must be 8000 characters or fewer.");
    }

    const systemInstruction =
      "You are a Biblical scholar assistant. Given text from a sermon, Bible page, or church bulletin, " +
      "identify scripture references, provide a summary, study notes, and discussion questions. " +
      "Always respond with valid JSON only, no markdown fences.";

    const userPrompt = `Analyze the following text for Biblical content:

${text}

Return JSON with exactly these fields:
{
  "scriptureRefs": ["e.g. John 3:16", "Romans 8:28"],
  "summary": "1-2 sentence summary of the main message",
  "studyNotes": ["insight 1", "insight 2", "..."],
  "discussionQuestions": ["question 1", "question 2", "..."],
  "confidence": 0.0
}
confidence should be 0.0–1.0 reflecting how confident you are this is Christian/Biblical content.`;

    logger.info(`bereanVisionScan: processing for uid=${userId}`);

    let result: BereanVisionScanResult;

    try {
      const { text: llmText, isMock } = await callGeminiText(systemInstruction, userPrompt, 0.2, 1024);

      if (isMock || !llmText) {
        result = BEREAN_VISION_MOCK;
      } else {
        const parsed = parseJsonFromLLM<{
          scriptureRefs?: string[];
          summary?: string;
          studyNotes?: string[];
          discussionQuestions?: string[];
          confidence?: number;
        }>(llmText);

        if (!parsed) {
          logger.warn("bereanVisionScan: JSON parse failed — returning mock.");
          result = BEREAN_VISION_MOCK;
        } else {
          result = {
            scriptureRefs: Array.isArray(parsed.scriptureRefs) ? parsed.scriptureRefs.map(String) : [],
            summary: String(parsed.summary ?? ""),
            studyNotes: Array.isArray(parsed.studyNotes) ? parsed.studyNotes.map(String) : [],
            discussionQuestions: Array.isArray(parsed.discussionQuestions)
              ? parsed.discussionQuestions.map(String)
              : [],
            confidence: typeof parsed.confidence === "number" ? Math.min(1, Math.max(0, parsed.confidence)) : 0,
            isMock: false,
          };
        }
      }
    } catch (err) {
      logger.error("bereanVisionScan: unexpected error.", { err: String(err) });
      throw new functions.HttpsError("internal", String(err));
    }

    logger.info(
      `bereanVisionScan: completed for uid=${userId}, refs=${result.scriptureRefs.length}, confidence=${result.confidence}`
    );
    return result;
  }
);

// ── scanMediaForSafety ────────────────────────────────────────────────────────

interface ScanMediaForSafetyResult {
  riskLevel: "low" | "medium" | "high" | "severe" | "critical";
  detectedItems: string[];
  sceneType: string;
  nudgeMessage: string | null;
  blocksPublish: boolean;
  containsMinor: boolean;
}

const SAFE_FALLBACK: ScanMediaForSafetyResult = {
  riskLevel: "low",
  detectedItems: [],
  sceneType: "unknown",
  nudgeMessage: null,
  blocksPublish: false,
  containsMinor: false,
};

export const scanMediaForSafety = functions.onCall(
  { enforceAppCheck: true, timeoutSeconds: 60 },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ScanMediaForSafetyRequest;
    const imageBase64 = String(data?.imageBase64 ?? "");
    const mimeType = String(data?.mimeType ?? "image/jpeg").trim();
    const safetyProfile = String(data?.safetyProfile ?? "default").trim();

    if (!imageBase64) throw new functions.HttpsError("invalid-argument", "imageBase64 is required.");

    // ── Max size guard: 4 MB base64 ───────────────────────────────────────────
    if (imageBase64.length > MAX_IMAGE_BASE64_BYTES) {
      throw new functions.HttpsError(
        "invalid-argument",
        "Image exceeds 4 MB base64 limit. Resize before submitting."
      );
    }

    const VALID_MIME_TYPES = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"];
    if (!VALID_MIME_TYPES.includes(mimeType)) {
      throw new functions.HttpsError("invalid-argument", `mimeType must be one of: ${VALID_MIME_TYPES.join(", ")}.`);
    }

    const systemInstruction =
      "You are a content safety classifier. Analyze this image for safety concerns. " +
      "IMPORTANT: Do NOT identify, name, or describe any individual person. For faces, only report whether any appear to be a minor (under 18). " +
      "Focus on: sensitive content, presence of faces (age detection only — no identity), PII visible in the image, and scene type. " +
      "Always respond with valid JSON only, no markdown fences.";

    const userPrompt = `Safety profile: ${safetyProfile}

Analyze this image and return JSON with exactly these fields:
{
  "riskLevel": "low" | "medium" | "high" | "severe" | "critical",
  "detectedItems": ["list of detected concern categories, empty if none"],
  "sceneType": "e.g. outdoor, indoor, church, text-document, selfie, crowd, nature",
  "nudgeMessage": "A friendly guidance message if riskLevel >= medium, null otherwise",
  "blocksPublish": true | false,
  "containsMinor": true | false
}

Risk level guide:
- low: No concerns
- medium: Minor concerns, soft nudge appropriate
- high: Significant concerns, strong nudge required
- severe: Serious violations, blocks publish
- critical: CSAM or extreme content, blocks publish immediately`;

    logger.info(`scanMediaForSafety: processing for uid=${userId}, profile=${safetyProfile}`);

    let result: ScanMediaForSafetyResult;

    try {
      const { text: llmText, isMock } = await callGeminiVision(
        systemInstruction,
        imageBase64,
        mimeType,
        userPrompt,
        1024
      );

      if (isMock || !llmText) {
        logger.info("scanMediaForSafety: Gemini not available — returning safe fallback.");
        result = SAFE_FALLBACK;
      } else {
        const parsed = parseJsonFromLLM<{
          riskLevel?: string;
          detectedItems?: string[];
          sceneType?: string;
          nudgeMessage?: string | null;
          blocksPublish?: boolean;
          containsMinor?: boolean;
        }>(llmText);

        if (!parsed) {
          logger.warn("scanMediaForSafety: JSON parse failed — returning safe fallback.");
          result = SAFE_FALLBACK;
        } else {
          const validRiskLevels = ["low", "medium", "high", "severe", "critical"] as const;
          const riskLevel = validRiskLevels.includes(parsed.riskLevel as (typeof validRiskLevels)[number])
            ? (parsed.riskLevel as ScanMediaForSafetyResult["riskLevel"])
            : "low";

          const blocksPublish =
            typeof parsed.blocksPublish === "boolean"
              ? parsed.blocksPublish
              : riskLevel === "severe" || riskLevel === "critical";

          result = {
            riskLevel,
            detectedItems: Array.isArray(parsed.detectedItems) ? parsed.detectedItems.map(String) : [],
            sceneType: String(parsed.sceneType ?? "unknown"),
            nudgeMessage: typeof parsed.nudgeMessage === "string" ? parsed.nudgeMessage : null,
            blocksPublish,
            containsMinor: Boolean(parsed.containsMinor ?? false),
          };
        }
      }
    } catch (err) {
      logger.error("scanMediaForSafety: unexpected error.", { err: String(err) });
      throw new functions.HttpsError("internal", String(err));
    }

    logger.info(
      `scanMediaForSafety: completed for uid=${userId}, riskLevel=${result.riskLevel}, blocks=${result.blocksPublish}`
    );
    return result;
  }
);

// ── reportCSAMFlag ────────────────────────────────────────────────────────────
//
// INTENTIONALLY MINIMAL LOGIC.
// This function is a secure audit-trail entry point only.
// It does NOT make automated decisions. All CSAM reports go to a human-review
// queue (csamReports collection) and are handled offline by trained reviewers.

export const reportCSAMFlag = functions.onCall(
  { enforceAppCheck: true, timeoutSeconds: 60 },
  async (request) => {
    // Strict auth gate — no anonymous submissions
    const userId = request.auth?.uid;
    if (!userId) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in to submit a report.");
    }

    const data = request.data as ReportCSAMFlagRequest;
    const reportId = String(data?.reportId ?? "").trim();
    const captureHash = String(data?.captureHash ?? "").trim();
    const reporterUid = String(data?.reporterUid ?? "").trim();

    if (!reportId) throw new functions.HttpsError("invalid-argument", "reportId is required.");
    if (!captureHash) throw new functions.HttpsError("invalid-argument", "captureHash is required.");
    if (!reporterUid) throw new functions.HttpsError("invalid-argument", "reporterUid is required.");

    // reporterUid in the payload must match the authenticated caller
    if (reporterUid !== userId) {
      throw new functions.HttpsError("permission-denied", "reporterUid must match the authenticated user.");
    }

    // ── Write to human-review queue only ──────────────────────────────────────
    const reportRef = db.collection("csamReports").doc(reportId);

    // Check for duplicate submission (idempotent)
    const existing = await reportRef.get();
    if (existing.exists) {
      logger.warn(`reportCSAMFlag: duplicate submission for reportId=${reportId} by uid=${userId}`);
      return {
        acknowledged: true,
        reportId,
        message: "Submitted for human review",
      };
    }

    await reportRef.set({
      reportId,
      captureHash,
      reporterUid,
      timestamp: FieldValue.serverTimestamp(),
      status: "pending_review",
      platform: "amenapp",
    });

    logger.warn(`reportCSAMFlag: CSAM report ${reportId} queued for human review. reporterUid=${userId}`);

    return {
      acknowledged: true,
      reportId,
      message: "Submitted for human review",
    };
  }
);
