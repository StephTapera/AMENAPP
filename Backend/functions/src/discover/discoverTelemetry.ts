import * as logger from "firebase-functions/logger";

const SAFE_STRING_FIELDS = new Set([
  "event",
  "feedbackType",
  "itemId",
  "sessionId",
  "surface",
  "source",
  "strategy",
  "uid",
]);

const SAFE_NUMBER_FIELDS = new Set([
  "candidate_count",
  "filtered_count",
  "latency_ms",
  "ranking_count",
  "safety_filtered_count",
  "visible_ms",
]);

const SAFE_BOOLEAN_FIELDS = new Set([
  "cached",
  "ok",
]);

function safeString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, 128);
}

function safeNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return value;
}

export function toSafeDiscoverTelemetryPayload(data: Record<string, unknown>): Record<string, unknown> {
  const payload: Record<string, unknown> = {};
  let copiedFieldCount = 0;

  for (const key of SAFE_STRING_FIELDS) {
    const value = safeString(data[key]);
    if (value !== undefined) {
      payload[key] = value;
      copiedFieldCount += 1;
    }
  }

  for (const key of SAFE_NUMBER_FIELDS) {
    const value = safeNumber(data[key]);
    if (value !== undefined) {
      payload[key] = value;
      copiedFieldCount += 1;
    }
  }

  for (const key of SAFE_BOOLEAN_FIELDS) {
    if (typeof data[key] === "boolean") {
      payload[key] = data[key];
      copiedFieldCount += 1;
    }
  }

  payload.inputFieldCount = Object.keys(data).length;
  payload.droppedFieldCount = Math.max(0, Object.keys(data).length - copiedFieldCount);
  return payload;
}

export function logDiscoverTelemetry(event: string, data: Record<string, unknown>): void {
  logger.info(`[discover] ${event}`, toSafeDiscoverTelemetryPayload(data));
}
