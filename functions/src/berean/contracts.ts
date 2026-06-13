// contracts.ts — Berean Island wire-format contracts (Wave 0)
//
// FROZEN after W0-GATE. Field names are wire-format law.
// Do not add, remove, rename, or retype anything in this file.
// File a Class C blocker if a contract change is needed.
//
// Swift naming deviations documented in BereanIslandContracts.swift.
// Wire-format string values are unaffected by Swift renames.

export type BereanIntent = "ask" | "discern" | "build" | "guard" | "reflect";

export interface ContextPacket {
  intent: BereanIntent;
  surface: string;
  fields: { signal: string; value: string; chip: { label: string; signal: string } }[];
  assembledAt: string; // ISO 8601
}

// Callable: bereanIsland_trigger
// Routes Island queries into the existing five-mode engine. Returns existing
// SSE stream session handle — does NOT reimplement streaming.
export interface IslandTriggerRequest {
  query: string;
  packet: ContextPacket;
  conversationId?: string;
}
export interface IslandTriggerResponse {
  streamSessionId: string;     // existing SSE session
  conversationId: string;
}

// Callable: bereanLens_analyze
export interface LensAnalyzeRequest {
  mode: "bible" | "sermon" | "flyer" | "study" | "safety" | "fellowship";
  ocrText?: string;            // prefer on-device OCR text over image upload
  imageRef?: string;           // Storage path, ONLY when image semantics required;
                               // upload allowed ONLY after client GUARDIAN pre-check pass
  packet: ContextPacket;
}
export interface LensAnalyzeResponse {
  card: IslandCardWire;
  safetyFlags: IslandSafetyFlagWire[];
  extracted?: unknown;         // discriminated by mode, see Swift LensExtraction
}

// Callable: writeWithBerean_assist
export interface WriteAssistRequest {
  tool: "draftTestimony" | "rewritePrayer" | "moreGracious" | "addScripture"
      | "toneCheck" | "explainWording" | "cleanThought";
  draft: string;
  surface: string;
  answers?: string[];          // draftTestimony interview answers
}
export interface WriteAssistResponse {
  revised?: string;            // ALWAYS returned as suggestion; client renders diff
  flags: IslandSafetyFlagWire[];
  citations?: IslandCitationWire[];
}

// Callable: sermonCompanion_session  (op-based, single endpoint)
export interface SermonSessionRequest {
  op: "start" | "appendTranscript" | "appendSlideOCR" | "end";
  sessionId?: string;
  text?: string;
  churchId?: string;           // checked against no-transcription opt-out registry
}
export interface SermonSessionResponse {
  sessionId: string;
  noteId: string;              // Smart Church Note being streamed into
  detectedVerses: IslandCitationWire[];
  summaryCard?: IslandCardWire; // present only on op="end"
  blocked?: "churchOptOut";    // start refused; client falls back to manual notes
}

export interface IslandCardWire {
  id: string;
  kind: string;
  header: string;
  body: string;
  sourceLine?: string;
  citations: IslandCitationWire[];
  actions: string[];
  aiAssisted: boolean;
  payload?: unknown;
}
export interface IslandCitationWire {
  reference: string;
  translation: string;
  verified: boolean;
}
export interface IslandSafetyFlagWire {
  check: string;
  severity: "note" | "friction" | "block";
  explanation: string;
  suggestion?: string;
}
