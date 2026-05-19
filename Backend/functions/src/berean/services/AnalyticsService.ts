// berean/services/AnalyticsService.ts
// Berean-specific analytics event logging.
// IMPORTANT: Never log raw private spiritual reflections.

import * as admin from "firebase-admin";

type BereanAnalyticsEvent =
  | "study_started"
  | "study_completed"
  | "passage_opened"
  | "graph_explored"
  | "immersion_opened"
  | "reflection_saved"
  | "prayer_prompt_opened"
  | "leadership_prompt_opened"
  | "follow_up_completed"
  | "sensitive_topic_redirected"
  | "cache_hit"
  | "cache_miss"
  | "llm_request_started"
  | "llm_request_completed"
  | "llm_request_failed"
  | "safety_violation_detected";

interface AnalyticsPayload {
  event: BereanAnalyticsEvent;
  userId: string;
  conversationId?: string;
  passageId?: string;
  responseMode?: string;
  latencyMs?: number;
  cacheHit?: boolean;
  metadata?: Record<string, string | number | boolean>;
}

const db = () => admin.firestore();
const REDACTED_TEXT_KEYS = new Set([
  "text",
  "texts",
  "bodyText",
  "bodyTexts",
  "noteText",
  "noteTexts",
  "noteBody",
  "noteBodies",
  "noteContent",
  "noteContents",
  "reflectionText",
  "reflectionTexts",
  "reflectionBody",
  "reflectionBodies",
  "rawText",
  "rawTexts",
  "rawPreview",
  "notePreview",
  "notePreviews",
]);

export class AnalyticsService {
  async log(payload: AnalyticsPayload): Promise<void> {
    // Fire and forget — analytics should never block response
    const ref = db().collection("berean_analytics_events").doc();
    ref
      .set({
        ...payload,
        metadata: this.sanitizeMetadata(payload.metadata),
        createdAt: admin.firestore.Timestamp.now(),
      })
      .catch((err) => {
        console.warn("[AnalyticsService] Failed to log event:", err);
      });
  }

  async logRequestStart(userId: string, conversationId: string): Promise<number> {
    const startTime = Date.now();
    this.log({ event: "llm_request_started", userId, conversationId });
    return startTime;
  }

  async logRequestComplete(
    userId: string,
    conversationId: string,
    startTime: number,
    cacheHit: boolean,
    responseMode: string
  ): Promise<void> {
    this.log({
      event: cacheHit ? "cache_hit" : "cache_miss",
      userId,
      conversationId,
      latencyMs: Date.now() - startTime,
      cacheHit,
      responseMode,
    });
    this.log({
      event: "llm_request_completed",
      userId,
      conversationId,
      latencyMs: Date.now() - startTime,
      responseMode,
    });
  }

  async logSafetyViolation(
    userId: string,
    conversationId: string,
    violations: string[]
  ): Promise<void> {
    this.log({
      event: "safety_violation_detected",
      userId,
      conversationId,
      metadata: {
        violationCount: violations.length,
        // Never log the actual violation text — it may contain sensitive content
      },
    });
  }

  sanitizeMetadata(
    metadata?: Record<string, string | number | boolean>
  ): Record<string, string | number | boolean> | undefined {
    if (!metadata) {
      return undefined;
    }

    const sanitized = Object.entries(metadata).reduce<Record<string, string | number | boolean>>(
      (acc, [key, value]) => {
        if (!REDACTED_TEXT_KEYS.has(key)) {
          acc[key] = value;
        }
        return acc;
      },
      {}
    );

    return Object.keys(sanitized).length > 0 ? sanitized : undefined;
  }
}

export const analyticsService = new AnalyticsService();
