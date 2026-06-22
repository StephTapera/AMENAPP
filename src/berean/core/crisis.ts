/**
 * crisis.ts — Berean Phase 2A
 *
 * Crisis detection + human-gate scaffold.
 *
 * Design invariants:
 *  1. detectCrisis() is keyword-only — no AI, no network call. Fast pre-screen.
 *  2. handleCrisis() calls the `bereanCrisisDetect` CF for AI signal, then
 *     SUPPRESSES the AI answer and surfaces hardcoded human crisis resources.
 *  3. getCrisisResources() returns hardcoded real US resources — NO AI content.
 *  4. buildCrisisPayload() constructs the HumanGatePayload for T&S.
 *
 * HUMAN GATE: T&S owns the crisis response queue. AI answer suppressed.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 2A Core Agent
 */

import { getFunctions, httpsCallable } from 'firebase/functions';

import type { HumanGatePayload } from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// CrisisResource — returned to the UI (hardcoded, no AI authorship)
// ─────────────────────────────────────────────────────────────────────────────

export interface CrisisResource {
  name: string;
  contact: string;
  description: string;
  url: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyword lists — intentionally broad to maximise recall over precision.
// False positives route to human resources (safe). False negatives miss crisis
// signals (unsafe). Err on the side of false positives.
// ─────────────────────────────────────────────────────────────────────────────

const CRISIS_KEYWORDS: readonly string[] = [
  // Suicidality
  'suicide', 'suicidal', 'kill myself', 'end my life', 'take my life',
  'want to die', 'don\'t want to live', 'don\'t want to be here anymore',
  'no reason to live', 'not worth living', 'life is not worth',
  'thinking about dying', 'planning to die',
  // Self-harm
  'self-harm', 'self harm', 'cut myself', 'cutting myself', 'hurt myself',
  'hurting myself', 'harm myself', 'harming myself',
  // Abuse (immediate safety)
  'being abused', 'he hits me', 'she hits me', 'they hit me',
  'domestic violence', 'being hurt', 'someone is hurting me',
  'unsafe at home', 'afraid for my life', 'in danger',
];

// ─────────────────────────────────────────────────────────────────────────────
// detectCrisis — fast keyword pre-screen (synchronous, no AI)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns true if the input contains any crisis keyword.
 * This is NOT an AI call. It runs synchronously as a fast pre-screen before
 * the callBerean pipeline. When true, handleCrisis() must be called instead
 * of callBerean(), and the AI answer MUST be suppressed.
 */
export function detectCrisis(input: string): boolean {
  if (!input || typeof input !== 'string') return false;
  const lower = input.toLowerCase();
  return CRISIS_KEYWORDS.some((kw) => lower.includes(kw));
}

// ─────────────────────────────────────────────────────────────────────────────
// buildCrisisPayload — T&S gate scaffold
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Builds a HumanGatePayload for T&S. The context object contains only opaque
 * signal metadata — no AI-authored content, no verbatim user message beyond
 * what is needed for T&S triage.
 */
export function buildCrisisPayload(
  userId: string,
  input: string,
): HumanGatePayload {
  return {
    reason: 'CRISIS_CONTENT',
    userId,
    timestamp: new Date().toISOString(),
    // context is opaque — no AI content; T&S owns the response queue
    context: {
      inputLength: String(input.length),
      detectionMethod: 'keyword_prescreen',
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// getCrisisResources — hardcoded US crisis resources (NO AI content)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns hardcoded, verified US crisis resources. These are NEVER AI-authored.
 * Update this list manually when resource details change.
 */
export function getCrisisResources(): CrisisResource[] {
  return [
    {
      name: '988 Suicide & Crisis Lifeline',
      contact: 'Call or text 988',
      description:
        'Free, confidential support for people in distress. Available 24/7.',
      url: 'https://988lifeline.org',
    },
    {
      name: 'Crisis Text Line',
      contact: 'Text HOME to 741741',
      description:
        'Text-based crisis support. Free, 24/7, confidential. Connects you with a trained crisis counselor.',
      url: 'https://www.crisistextline.org',
    },
    {
      name: 'National Domestic Violence Hotline',
      contact: '1-800-799-7233 (1-800-799-SAFE)',
      description:
        'Confidential support for those experiencing domestic violence or abuse. Available 24/7.',
      url: 'https://www.thehotline.org',
    },
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// handleCrisis — AI detection + human resources (AI answer always suppressed)
// ─────────────────────────────────────────────────────────────────────────────

interface CrisisHandleResult {
  crisisDetected: boolean;
  resources: CrisisResource[];
  humanGatePayload: HumanGatePayload;
}

interface BereanCrisisDetectRequest {
  input: string;
}

interface BereanCrisisDetectResponse {
  crisisDetected: boolean;
}

/**
 * Calls the `bereanCrisisDetect` CF for AI-based detection signal, then:
 *  - SUPPRESSES any AI answer (never returned to the caller)
 *  - Returns hardcoded crisis resources for the UI to display
 *  - Returns the HumanGatePayload scaffold for T&S
 *
 * HUMAN GATE: T&S owns the crisis response queue. AI answer suppressed.
 *
 * If the CF call fails, defaults to crisisDetected: true (fail-safe — always
 * surface resources on uncertainty).
 */
export async function handleCrisis(
  userId: string,
  input: string,
): Promise<CrisisHandleResult> {
  // HUMAN GATE: T&S owns the crisis response queue. AI answer suppressed.

  const humanGatePayload = buildCrisisPayload(userId, input);
  const resources = getCrisisResources();

  let crisisDetected = true; // default fail-safe

  try {
    const functions = getFunctions();
    const detectCF = httpsCallable<BereanCrisisDetectRequest, BereanCrisisDetectResponse>(
      functions,
      'bereanCrisisDetect',
    );

    const result = await detectCF({ input });
    crisisDetected = result.data.crisisDetected;
  } catch {
    // CF call failed — keep crisisDetected: true (safe default)
  }

  return {
    crisisDetected,
    resources,
    humanGatePayload,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Named export object (for BereanCore context value)
// ─────────────────────────────────────────────────────────────────────────────

export const crisisService = {
  detectCrisis,
  buildCrisisPayload,
  getCrisisResources,
  handleCrisis,
};
