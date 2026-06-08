/**
 * aiActivityLogger.js
 * Centralized AI call logging for AMEN Cloud Functions.
 *
 * Every AI invocation (NVIDIA, Claude, Vertex, Gemini) SHOULD call logAIActivity()
 * so we have a unified audit trail for:
 *   - Cost tracking (tokens × cost_per_token)
 *   - Latency monitoring
 *   - Per-user AI usage quotas
 *   - Bias / drift detection
 *   - Moderation decision audit
 *
 * HARD RULES:
 *   - NEVER log raw input text or raw AI output — only metadata.
 *   - Input is captured as charCount + contentType only.
 *   - Output is captured as charCount + decision/classification only.
 *   - Log writes are best-effort (fire-and-forget); never block the main call.
 *
 * Firestore path: aiActivityLog/{logId}
 */

"use strict";

const admin = require("firebase-admin");

const COLLECTION = "aiActivityLog";

/**
 * Log a single AI invocation.  Call this inside your AI functions.
 * All fields are optional except uid and feature — never block on failure.
 *
 * @param {{
 *   uid:           string,         // authenticated user id
 *   feature:       string,         // e.g. "checkContentSafety", "bereanRAG", "churchNotesASR"
 *   provider:      string,         // "nvidia" | "openai" | "anthropic" | "google" | "vertex"
 *   model?:        string,         // model name used
 *   inputChars?:   number,         // length of input text (NOT the text itself)
 *   outputChars?:  number,         // length of output text
 *   latencyMs?:    number,         // end-to-end latency
 *   decision?:     string,         // "allow" | "block" | "warn" | "review" | "draft" etc.
 *   success:       boolean,        // did the AI call succeed?
 *   errorCode?:    string,         // error code if !success
 *   featureFlag?:  string,         // Remote Config flag guarding this feature
 * }} params
 */
async function logAIActivity(params) {
  const {
    uid,
    feature,
    provider = "nvidia",
    model,
    inputChars,
    outputChars,
    latencyMs,
    decision,
    success,
    errorCode,
    featureFlag,
  } = params;

  if (!uid || !feature) return; // minimal guard — never throw

  const doc = {
    uid,
    feature,
    provider,
    success: !!success,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (model)        doc.model        = model;
  if (inputChars)   doc.inputChars   = inputChars;
  if (outputChars)  doc.outputChars  = outputChars;
  if (latencyMs)    doc.latencyMs    = latencyMs;
  if (decision)     doc.decision     = decision;
  if (errorCode)    doc.errorCode    = errorCode;
  if (featureFlag)  doc.featureFlag  = featureFlag;

  try {
    await admin.firestore().collection(COLLECTION).add(doc);
  } catch (err) {
    // Best-effort: never let logging failure propagate to the caller
    console.error(`[aiActivityLogger] Failed to write log for uid=${uid} feature=${feature}:`, err.message);
  }
}

/**
 * Wrap an async AI call with automatic latency + success/error logging.
 *
 * @param {Object} logParams  — same as logAIActivity but without success/latencyMs/errorCode
 * @param {Function} fn       — async function to wrap
 * @returns Promise<any>      — result of fn(), re-throws on error (after logging)
 */
async function withAILogging(logParams, fn) {
  const start = Date.now();
  try {
    const result = await fn();
    const latencyMs = Date.now() - start;
    // Fire-and-forget logging
    logAIActivity({ ...logParams, success: true, latencyMs }).catch(() => {});
    return result;
  } catch (err) {
    const latencyMs = Date.now() - start;
    logAIActivity({
      ...logParams,
      success:   false,
      latencyMs,
      errorCode: err.code || err.message?.slice(0, 50),
    }).catch(() => {});
    throw err; // re-throw so the caller still sees the error
  }
}

/**
 * getAIUsageSummary — callable
 * Returns a per-user summary of AI activity from the last N days.
 * Used by admin console and per-user AI usage dashboard (AmenAIUsageLabel.swift).
 *
 * Request:  { days?: number }   defaults to 7
 * Response: { totalCalls, byFeature, byProvider, avgLatencyMs }
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");

exports.getAIUsageSummary = onCall(
  { region: "us-central1", timeoutSeconds: 20 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid  = request.auth.uid;
    const days = Math.min(Number(request.data?.days ?? 7), 30);
    const since = new Date(Date.now() - days * 86_400_000);

    const snap = await admin.firestore()
      .collection(COLLECTION)
      .where("uid",       "==",  uid)
      .where("createdAt", ">=",  admin.firestore.Timestamp.fromDate(since))
      .orderBy("createdAt", "desc")
      .limit(500)
      .get();

    if (snap.empty) {
      return { totalCalls: 0, byFeature: {}, byProvider: {}, avgLatencyMs: null };
    }

    const byFeature  = {};
    const byProvider = {};
    let   totalLatency = 0;
    let   latencyCount = 0;

    snap.docs.forEach((doc) => {
      const d = doc.data();
      byFeature[d.feature]   = (byFeature[d.feature]   || 0) + 1;
      byProvider[d.provider] = (byProvider[d.provider] || 0) + 1;
      if (d.latencyMs) { totalLatency += d.latencyMs; latencyCount++; }
    });

    return {
      totalCalls:   snap.size,
      byFeature,
      byProvider,
      avgLatencyMs: latencyCount > 0 ? Math.round(totalLatency / latencyCount) : null,
    };
  }
);

module.exports = { logAIActivity, withAILogging };
// Named exports also on module.exports for callable registration
module.exports.getAIUsageSummary = exports.getAIUsageSummary;
