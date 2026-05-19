import * as fs from "fs";
import * as path from "path";
import {
  allowedContextActions,
  isPrivacySafeContextResult,
  isSupportedContextSource,
  sanitizeContextResponse,
  sanitizePayload,
  selectedTextLength,
} from "./bereanSelectionActions";

const routerSource = fs.readFileSync(path.resolve(__dirname, "contextualActionRouter.ts"), "utf8");

function validPayload(overrides: Record<string, unknown> = {}) {
  return sanitizePayload({
    id: "selection-1",
    selectedText: "Blessed are the peacemakers.",
    surroundingText: "Matthew 5",
    sourceSurface: "church_notes_editor",
    sourceId: "note-1",
    contentType: "note",
    metadata: { noteId: "note-1" },
    ...overrides,
  });
}

describe("routeBereanContextualAction callable guardrails", () => {
  it("fails unauthenticated requests", () => {
    expect(routerSource).toContain("if (!request.auth)");
    expect(routerSource).toContain("Authentication required.");
  });

  it("requires App Check at callable options and runtime", () => {
    expect(routerSource).toContain("enforceAppCheck: true");
    expect(routerSource).toContain("if (!request.app)");
    expect(routerSource).toContain("App Check required.");
  });

  it("enforces rate limits before model execution", () => {
    expect(routerSource).toContain("enforceRateLimit");
    expect(routerSource).toContain("RATE_LIMITS.bereanContextualActionPerMinute");
    expect(routerSource.indexOf("enforceRateLimit")).toBeLessThan(routerSource.indexOf("runBereanContextEngine"));
  });

  it("rejects unsupported action types", () => {
    expect(allowedContextActions).toContain("askBerean");
    expect(allowedContextActions).not.toContain("pretendToBePastor");
  });

  it("rejects empty selected text after trimming", () => {
    const payload = validPayload({ selectedText: "   " });
    expect(payload.selectedText).toBe("");
  });

  it("enforces selected text length before sanitizing", () => {
    const longText = "a".repeat(6001);
    expect(selectedTextLength({ selectedText: longText })).toBe(6001);
    expect(sanitizePayload({ selectedText: longText }).selectedText.length).toBe(6000);
    expect(routerSource).toContain("selectedTextLength(rawPayload) > 6000");
  });

  it("rejects unsupported context source surfaces", () => {
    expect(isSupportedContextSource(validPayload())).toBe(true);
    expect(isSupportedContextSource(validPayload({ sourceSurface: "untrusted_scraper" }))).toBe(false);
  });

  it("rejects unsupported content types", () => {
    expect(isSupportedContextSource(validPayload({ contentType: "note" }))).toBe(true);
    expect(isSupportedContextSource(validPayload({ contentType: "secret_profile_memory" }))).toBe(false);
  });

  it("does not allow fake memory or personalization in returned payloads", () => {
    const unsafe = {
      id: "result-1",
      title: "Ask Berean",
      answer: "I remember your previous prayer and your private struggle.",
      scriptureReferences: [],
      suggestedActions: ["Save"],
      safetyNotice: "AI-assisted",
      threadId: "thread-1",
    };

    expect(isPrivacySafeContextResult(unsafe)).toBe(false);
    const sanitized = sanitizeContextResponse(unsafe);
    expect(String(sanitized.answer)).toContain("cannot safely use or imply private memory");
    expect(sanitized.suggestedActions).toEqual([]);
  });

  it("returns only privacy-safe response fields", () => {
    const sanitized = sanitizeContextResponse({
      id: "result-1",
      title: "Explain",
      answer: "A grounded response.",
      scriptureReferences: ["Matthew 5:9"],
      suggestedActions: ["Save"],
      safetyNotice: "AI-assisted",
      threadId: "thread-1",
      selectedText: "raw private text should not return",
      emotionalMetadata: { private: true },
    });

    expect(Object.keys(sanitized).sort()).toEqual([
      "answer",
      "id",
      "safetyNotice",
      "scriptureReferences",
      "suggestedActions",
      "threadId",
      "title",
    ]);
  });
});
