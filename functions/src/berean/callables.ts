// callables.ts — Berean Island stub callables (Wave 0)
//
// All four callables are App-Check-enforced stubs that validate request shape
// and return typed mock responses. Real logic wired in Wave 1+.

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  ContextPacket,
  IslandTriggerRequest,
  IslandTriggerResponse,
  LensAnalyzeRequest,
  LensAnalyzeResponse,
  WriteAssistRequest,
  WriteAssistResponse,
  SermonSessionRequest,
  SermonSessionResponse,
  IslandCardWire,
  IslandCitationWire,
  IslandSafetyFlagWire,
} from "./contracts";

// ── Shared helpers ─────────────────────────────────────────────────────────────

function validateContextPacket(packet: unknown): packet is ContextPacket {
  if (!packet || typeof packet !== "object") return false;
  const p = packet as Record<string, unknown>;
  return (
    typeof p.intent === "string" &&
    typeof p.surface === "string" &&
    Array.isArray(p.fields) &&
    typeof p.assembledAt === "string"
  );
}

function mockCard(kind: string): IslandCardWire {
  return {
    id: `mock-${Date.now()}`,
    kind,
    header: "[stub] Berean Island W0",
    body: "This is a stub response. Real content arrives in Wave 1.",
    citations: [],
    actions: ["save", "share"],
    aiAssisted: false,
  };
}

function mockCitation(): IslandCitationWire {
  return { reference: "John 15:5", translation: "BSB", verified: true };
}

function mockSafetyFlag(check: string): IslandSafetyFlagWire {
  return { check, severity: "note", explanation: "[stub] example flag" };
}

// ── bereanIsland_trigger ───────────────────────────────────────────────────────
// Routes Island queries into the existing five-mode engine (stub: returns mock SSE handle).

export const bereanIsland_trigger = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<IslandTriggerResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const body = request.data as Partial<IslandTriggerRequest>;

    if (typeof body.query !== "string" || !body.query.trim()) {
      throw new functions.HttpsError("invalid-argument", "query is required");
    }
    if (!validateContextPacket(body.packet)) {
      throw new functions.HttpsError("invalid-argument", "packet is malformed");
    }

    logger.info("[BI-W0] bereanIsland_trigger stub", {
      uid,
      surface: body.packet.surface,
      intent: body.packet.intent,
      queryLength: body.query.length,
    });

    // Stub: return a mock SSE session handle. Wave 1 wires real engine.
    const stub: IslandTriggerResponse = {
      streamSessionId: `stub-sse-${Date.now()}`,
      conversationId: body.conversationId ?? `stub-conv-${Date.now()}`,
    };
    return stub;
  }
);

// ── bereanLens_analyze ─────────────────────────────────────────────────────────
// Analyzes camera-captured text/images via the Berean Lens pipeline (stub).

export const bereanLens_analyze = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<LensAnalyzeResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const body = request.data as Partial<LensAnalyzeRequest>;

    const validModes = ["bible", "sermon", "flyer", "study", "safety", "fellowship"];
    if (!body.mode || !validModes.includes(body.mode)) {
      throw new functions.HttpsError("invalid-argument", "mode must be one of: " + validModes.join(", "));
    }
    if (!validateContextPacket(body.packet)) {
      throw new functions.HttpsError("invalid-argument", "packet is malformed");
    }
    if (!body.ocrText && !body.imageRef) {
      throw new functions.HttpsError("invalid-argument", "ocrText or imageRef is required");
    }

    logger.info("[BI-W0] bereanLens_analyze stub", {
      uid,
      mode: body.mode,
      hasOcr: !!body.ocrText,
      hasImageRef: !!body.imageRef,
    });

    const stub: LensAnalyzeResponse = {
      card: mockCard(body.mode === "flyer" ? "event" : "verse"),
      safetyFlags: [],
    };

    if (body.mode === "bible") {
      stub.card.citations = [mockCitation()];
    }
    if (body.mode === "safety") {
      stub.safetyFlags = [mockSafetyFlag("faceConsent")];
    }

    return stub;
  }
);

// ── writeWithBerean_assist ─────────────────────────────────────────────────────
// Writing tools for composers: tone check, gracious rewrite, scripture, etc. (stub).

export const writeWithBerean_assist = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<WriteAssistResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const body = request.data as Partial<WriteAssistRequest>;

    const validTools = [
      "draftTestimony", "rewritePrayer", "moreGracious", "addScripture",
      "toneCheck", "explainWording", "cleanThought",
    ];
    if (!body.tool || !validTools.includes(body.tool)) {
      throw new functions.HttpsError("invalid-argument", "tool must be one of: " + validTools.join(", "));
    }
    if (typeof body.draft !== "string") {
      throw new functions.HttpsError("invalid-argument", "draft is required");
    }
    if (typeof body.surface !== "string") {
      throw new functions.HttpsError("invalid-argument", "surface is required");
    }
    // draftTestimony: must decline fabrication when no answers provided
    if (body.tool === "draftTestimony" && (!body.answers || body.answers.length === 0)) {
      throw new functions.HttpsError(
        "failed-precondition",
        "Berean cannot draft a testimony without your story. Please answer the interview questions first."
      );
    }

    logger.info("[BI-W0] writeWithBerean_assist stub", {
      uid,
      tool: body.tool,
      surface: body.surface,
      draftLength: body.draft.length,
    });

    const stub: WriteAssistResponse = {
      revised: body.tool === "toneCheck"
        ? undefined
        : `[stub] ${body.tool} suggestion for: "${body.draft.substring(0, 40)}..."`,
      flags: body.tool === "toneCheck" ? [mockSafetyFlag("harshTone")] : [],
      citations: body.tool === "addScripture" ? [mockCitation()] : undefined,
    };
    return stub;
  }
);

// ── sermonCompanion_session ────────────────────────────────────────────────────
// Op-based sermon note streaming: start / appendTranscript / appendSlideOCR / end (stub).

export const sermonCompanion_session = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<SermonSessionResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const body = request.data as Partial<SermonSessionRequest>;

    const validOps = ["start", "appendTranscript", "appendSlideOCR", "end"];
    if (!body.op || !validOps.includes(body.op)) {
      throw new functions.HttpsError("invalid-argument", "op must be one of: " + validOps.join(", "));
    }
    if (body.op !== "start" && !body.sessionId) {
      throw new functions.HttpsError("invalid-argument", "sessionId required for op: " + body.op);
    }

    logger.info("[BI-W0] sermonCompanion_session stub", {
      uid,
      op: body.op,
      sessionId: body.sessionId,
      churchId: body.churchId,
    });

    const sessionId = body.sessionId ?? `stub-session-${Date.now()}`;
    const noteId = `stub-note-${Date.now()}`;

    // Stub church opt-out check (real registry wired in Wave 5)
    if (body.op === "start" && body.churchId === "test-optout-church") {
      return { sessionId, noteId, detectedVerses: [], blocked: "churchOptOut" };
    }

    const stub: SermonSessionResponse = {
      sessionId,
      noteId,
      detectedVerses: body.op === "appendTranscript" ? [mockCitation()] : [],
      summaryCard: body.op === "end" ? mockCard("sermon") : undefined,
    };
    return stub;
  }
);
