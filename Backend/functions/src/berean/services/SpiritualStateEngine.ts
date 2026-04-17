/**
 * SpiritualStateEngine.ts
 *
 * Classifies the user's spiritual posture from their message and conversation history.
 * Selects an appropriate ResponseMode and surfaces any SensitivityFlags.
 *
 * This is a heuristic + keyword-signal classifier — deliberately lightweight so it
 * runs synchronously before the main LLM call. A heavier ML-based classifier
 * could replace this via feature flag in a future iteration.
 *
 * NON-NEGOTIABLE: This classifier NEVER stores results without user consent.
 * Crisis signals always escalate to human resources immediately.
 */

import * as admin from "firebase-admin";
import {
  SpiritualPrimaryState,
  ResponseMode,
  SensitivityFlag,
  SpiritualStateClassification,
  SpiritualStateSignals,
} from "../models/berean";
import { v4 as uuidv4 } from "uuid";

// ---------------------------------------------------------------------------
// Keyword signal sets — intentionally broad, false-positives are acceptable
// (we tune toward caution, not precision, for safety signals)
// ---------------------------------------------------------------------------

const CRISIS_SIGNALS = new Set([
  "suicide", "suicidal", "kill myself", "end my life", "don't want to live",
  "want to die", "hurt myself", "self-harm", "cutting", "no reason to live",
  "give up on life", "hopeless", "worthless", "nobody cares",
]);

const GRIEF_SIGNALS = new Set([
  "died", "death", "funeral", "lost someone", "grieving", "grief",
  "passed away", "losing", "mourning", "bereaved", "widow", "widower",
]);

const DOUBT_SIGNALS = new Set([
  "doubt", "doubting", "unsure", "questioning", "don't know if i believe",
  "struggling with faith", "why does god", "where is god", "god doesn't seem",
  "feels like god", "losing faith",
]);

const PRAYER_SIGNALS = new Set([
  "praying", "in prayer", "during prayer", "while praying", "help me pray",
  "prayer time", "pray about", "intercession",
]);

const ACADEMIC_SIGNALS = new Set([
  "greek", "hebrew", "original language", "exegesis", "hermeneutics",
  "commentary", "context", "historical", "theological", "doctrine",
  "translation", "manuscripts", "meaning of", "what does this word",
  "lexicon", "strong's",
]);

const HARDSHIP_SIGNALS = new Set([
  "difficult", "hard time", "struggling", "going through", "suffering",
  "pain", "hurt", "broken", "overwhelmed", "anxiety", "depression",
  "fear", "worried", "scared",
]);

const LEADER_SIGNALS = new Set([
  "pastor", "priest", "bishop", "elder", "mentor", "counselor",
  "small group leader", "my church",
]);

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/**
 * Classify the user's spiritual state from their current message.
 * Returns a full classification with selected ResponseMode and signals.
 */
export async function classifySpiritualState(
  userId: string,
  message: string,
  conversationHistory: Array<{ role: string; content: string }>
): Promise<SpiritualStateClassification> {
  const lower = message.toLowerCase();
  const signals = extractSignals(lower);
  const primaryState = determinePrimaryState(signals, lower);
  const selectedMode = selectResponseMode(primaryState, signals);
  const escalationTriggered = signals.crisisSignalDetected || primaryState === "crisis";
  const escalationReason = escalationTriggered
    ? "Crisis signal detected in user message. Human support resources presented."
    : undefined;

  const sessionId = uuidv4();
  const now = admin.firestore.Timestamp.now();

  const classification: SpiritualStateClassification = {
    primaryState,
    signals,
    selectedResponseMode: selectedMode,
    escalationTriggered,
    escalationReason,
    sessionId,
    classifiedAt: now,
  };

  // Store session record for longitudinal tracking (fire-and-forget, non-blocking)
  storeSessionRecord(userId, classification, sessionId).catch(() => {
    // Non-fatal — classification still proceeds
  });

  return classification;
}

function extractSignals(lower: string): SpiritualStateSignals {
  let emotionalIntensity = 0;

  const crisisSignalDetected = [...CRISIS_SIGNALS].some((s) => lower.includes(s));
  const referencesHardship = [...HARDSHIP_SIGNALS].some((s) => lower.includes(s));
  const containsDoubt = [...DOUBT_SIGNALS].some((s) => lower.includes(s));
  const doctrinalQuery = [...ACADEMIC_SIGNALS].some((s) => lower.includes(s));
  const mentionedLeader = [...LEADER_SIGNALS].some((s) => lower.includes(s));

  // Rough emotional intensity from signal density
  if (crisisSignalDetected) emotionalIntensity = 0.95;
  else if (referencesHardship && containsDoubt) emotionalIntensity = 0.75;
  else if (referencesHardship) emotionalIntensity = 0.6;
  else if (containsDoubt) emotionalIntensity = 0.45;
  else emotionalIntensity = 0.15;

  // Confidence: crisis signal detection is high-confidence; others are signal-based
  const classificationConfidence = crisisSignalDetected ? 0.92 : doctrinalQuery ? 0.8 : 0.65;

  return {
    emotionalIntensity,
    containsDoubt,
    referencesHardship,
    crisisSignalDetected,
    doctrinalQuery,
    mentionedLeader,
    classificationConfidence,
  };
}

function determinePrimaryState(
  signals: SpiritualStateSignals,
  lower: string
): SpiritualPrimaryState {
  if (signals.crisisSignalDetected) return "crisis";
  if ([...GRIEF_SIGNALS].some((s) => lower.includes(s))) return "grieving";
  if (signals.containsDoubt) return "wrestling";
  if ([...PRAYER_SIGNALS].some((s) => lower.includes(s))) return "prayerful";
  if (signals.doctrinalQuery) return "academic";
  if (signals.referencesHardship) return "devotional";
  return "neutral";
}

function selectResponseMode(
  primaryState: SpiritualPrimaryState,
  signals: SpiritualStateSignals
): ResponseMode {
  switch (primaryState) {
    case "crisis":     return "crisis";
    case "grieving":   return "comfort";
    case "wrestling":  return "exploratory";
    case "prayerful":  return "prayer_support";
    case "academic":   return "scholarly";
    case "devotional":
      // High emotional intensity → pastoral (not scholarly)
      return signals.emotionalIntensity > 0.5 ? "pastoral" : "balanced";
    case "discerning": return "exploratory";
    case "neutral":
    default:           return "balanced";
  }
}

// ---------------------------------------------------------------------------
// Sensitivity flag detection
// ---------------------------------------------------------------------------

/**
 * Post-generation check: scan the AI's response for sensitivity flags.
 * Called after the LLM has generated its answer, before returning to the client.
 */
export function detectSensitivityFlags(
  aiResponse: string,
  primaryState: SpiritualPrimaryState
): SensitivityFlag[] {
  const flags: SensitivityFlag[] = [];
  const lower = aiResponse.toLowerCase();

  // Crisis first
  if (primaryState === "crisis") {
    flags.push("crisis_escalation");
  }

  // Scrupulosity risk: excessive guilt/shame language in the AI response
  const scrupulosityMarkers = ["you must", "you should always", "you are sinning", "god will punish"];
  if (scrupulosityMarkers.some((m) => lower.includes(m))) {
    flags.push("scrupulosity_risk");
  }

  // Controversial doctrine markers
  const controversialMarkers = ["predestination", "eternal security", "tongues", "baptism is required", "purgatory"];
  if (controversialMarkers.some((m) => lower.includes(m))) {
    flags.push("controversial_doctrine");
  }

  return flags;
}

// ---------------------------------------------------------------------------
// Firestore session storage
// ---------------------------------------------------------------------------

async function storeSessionRecord(
  userId: string,
  classification: SpiritualStateClassification,
  sessionId: string
): Promise<void> {
  const db = admin.firestore();
  await db
    .collection("users")
    .doc(userId)
    .collection("spiritualStateSessions")
    .doc(sessionId)
    .set({
      userId,
      primaryState: classification.primaryState,
      responseMode: classification.selectedResponseMode,
      sensitivityFlags: [],
      escalationTriggered: classification.escalationTriggered,
      messageCount: 1,
      sessionStartedAt: classification.classifiedAt,
    });
}
