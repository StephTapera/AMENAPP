// churchNotesContext.test.js
// Contract tests for the Church Notes Context Engine.
// Uses file-reading contract approach (matches existing test patterns in this codebase).
// Tests: provenance labels, permission boundaries, private note protection,
// approval gates, recap language guardrails, group privacy, Firestore paths.
//
// Run: node --test tests/churchNotesContext.test.js

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const srcDir = path.join(__dirname, "..", "src", "churchNotesContext");
const rulesPath = path.join(__dirname, "..", "..", "firestore.rules");

// MARK: - Source File Helpers

function readSrc(filename) {
  return fs.readFileSync(path.join(srcDir, filename), "utf8");
}

function rulesContent() {
  return fs.readFileSync(rulesPath, "utf8");
}

// MARK: - Types Contract

test("types.ts defines CN_MAX_INPUT_CHARS", () => {
  const src = readSrc("types.ts");
  assert.ok(src.includes("CN_MAX_INPUT_CHARS"), "types.ts must define CN_MAX_INPUT_CHARS");
  assert.ok(src.includes("CN_MAX_OUTPUT_CHARS"), "types.ts must define CN_MAX_OUTPUT_CHARS");
});

test("CN_SYSTEM_PROMPT_HEADER enforces humble language guardrails", () => {
  const src = readSrc("types.ts");
  assert.ok(src.includes("CN_SYSTEM_PROMPT_HEADER"), "types.ts must define CN_SYSTEM_PROMPT_HEADER");
  assert.ok(src.includes("Never claim divine certainty"),
    "System prompt must include the divine certainty guardrail");
  assert.ok(src.includes("Never say: \"God told"),
    "System prompt must explicitly forbid 'God told you' language");
  assert.ok(!src.includes("God is telling you"),
    "System prompt must not contain the forbidden phrase 'God is telling you'");
});

test("types.ts defines all required context types", () => {
  const src = readSrc("types.ts");
  const requiredTypes = [
    "CNProvenanceLabel",
    "CNApprovalState",
    "CNContextResult",
    "CNSmartRecap",
    "CNMemorySnapshot",
    "CNExtractedAction",
    "CNGrowthTimelineEntry",
    "CNGroupInsight",
  ];
  for (const type of requiredTypes) {
    assert.ok(src.includes(type), `types.ts must define ${type}`);
  }
});

test("CNApprovalState includes all required states", () => {
  const src = readSrc("types.ts");
  assert.ok(src.includes('"pending"'), "Must have pending state");
  assert.ok(src.includes('"approved"'), "Must have approved state");
  assert.ok(src.includes('"edited"'), "Must have edited state");
  assert.ok(src.includes('"rejected"'), "Must have rejected state");
});

// MARK: - Context Engine

test("context engine uses Claude Haiku model", () => {
  const src = readSrc("churchNotesContextEngine.ts");
  assert.ok(src.includes("claude-haiku"), "Context engine must use Claude Haiku model");
});

test("context engine uses CN_SYSTEM_PROMPT_HEADER", () => {
  const src = readSrc("churchNotesContextEngine.ts");
  assert.ok(src.includes("CN_SYSTEM_PROMPT_HEADER"), "Context engine must use the system prompt header with guardrails");
});

test("context engine persists to server-owned path", () => {
  const src = readSrc("churchNotesContextEngine.ts");
  assert.ok(src.includes("churchNotes") && src.includes("context"),
    "Context engine must write to churchNotes/{noteId}/context");
});

test("context engine has scripture detection without LLM", () => {
  const src = readSrc("churchNotesContextEngine.ts");
  assert.ok(src.includes("SCRIPTURE_PATTERN"),
    "Scripture detection must use a regex pattern (no LLM needed for direct references)");
  assert.ok(src.includes("detectScriptureReferences"),
    "Must have detectScriptureReferences function");
});

// MARK: - Memory Engine Privacy

test("memory engine writes to users/ private path only", () => {
  const src = readSrc("churchNotesMemoryEngine.ts");
  assert.ok(src.includes("users"), "Memory must write to users/ path");
  assert.ok(src.includes("churchNotesMemory"), "Memory must use churchNotesMemory subcollection");
  assert.ok(!src.includes(".collection('groups')"),
    "Memory engine must not write to groups collection");
  assert.ok(!src.includes(".collection(\"groups\")"),
    "Memory engine must not write to groups collection (double quotes)");
});

test("memory engine uses prior note summaries not raw content", () => {
  const src = readSrc("churchNotesMemoryEngine.ts");
  assert.ok(src.includes("summaryDraft") || src.includes("transcriptText"),
    "Memory engine should use approved summaries/transcripts, not raw block content");
  assert.ok(src.includes(".slice(0,") || src.includes("slice(0,"),
    "Memory engine must truncate inputs to protect privacy and cost");
});

// MARK: - Recap Engine Language

test("recap engine uses humble language in prompt", () => {
  const src = readSrc("churchNotesRecapEngine.ts");
  assert.ok(src.includes("CN_SYSTEM_PROMPT_HEADER"), "Recap engine must use system prompt header");
  assert.ok(src.includes("A recurring theme appears to be") || src.includes("appears to be"),
    "Recap prompt must include humble framing examples");
  assert.ok(!src.includes("God is telling"),
    "Recap engine must not contain forbidden language");
});

test("recap is marked as server-owned write", () => {
  const src = readSrc("churchNotesRecapEngine.ts");
  assert.ok(src.includes("recaps"),
    "Recap must write to the recaps subcollection");
  assert.ok(src.includes("set(recap"),
    "Recap must be written via server-side set() call");
});

// MARK: - Action Extraction Approval Gate

test("extracted actions always start as pending", () => {
  const src = readSrc("churchNotesActionExtractionEngine.ts");
  assert.ok(src.includes('"pending"') || src.includes("'pending'"),
    "Extracted actions must have approvalState: 'pending'");
  assert.ok(src.includes("approvalState"),
    "Action extraction must set approvalState field");
});

test("action extraction uses approved content only", () => {
  const src = readSrc("churchNotesActionExtractionEngine.ts");
  assert.ok(src.includes("approvedTranscriptText") || src.includes("approvedOcrText"),
    "Action extraction must only use approved content from processing jobs");
});

test("action extraction writes to actions subcollection", () => {
  const src = readSrc("churchNotesActionExtractionEngine.ts");
  assert.ok(src.includes("actions"),
    "Action extraction must write to actions subcollection");
});

// MARK: - Growth Timeline Privacy

test("growth timeline entries have isPrivate: true enforced", () => {
  const src = readSrc("churchNotesGrowthTimelineEngine.ts");
  assert.ok(src.includes("isPrivate: true"),
    "Growth timeline must set isPrivate: true on all entries");
});

test("growth timeline writes to users/ private path", () => {
  const src = readSrc("churchNotesGrowthTimelineEngine.ts");
  assert.ok(src.includes("users") && src.includes("churchNotesMemory"),
    "Growth timeline must write to users/{uid}/churchNotesMemory");
});

test("growth timeline never writes to churchNotes/ directly", () => {
  const src = readSrc("churchNotesGrowthTimelineEngine.ts");
  // Growth timeline is private to the user, not on the note document
  const churchNotesWrite = src.includes('collection("churchNotes")') && src.includes(".set(");
  assert.ok(!churchNotesWrite,
    "Growth timeline must not write to churchNotes/ collection directly");
});

// MARK: - Callable Security

test("all callables enforce App Check", () => {
  const src = readSrc("callable.ts");
  const callableMatches = src.match(/enforceAppCheck:\s*true/g) ?? [];
  assert.ok(callableMatches.length >= 5,
    `All 5 callables must set enforceAppCheck: true (found ${callableMatches.length})`);
});

test("all callables check auth.uid", () => {
  const src = readSrc("callable.ts");
  const authChecks = src.match(/req\.auth\?\.uid/g) ?? [];
  assert.ok(authChecks.length >= 5,
    `All 5 callables must check req.auth?.uid (found ${authChecks.length})`);
});

test("callables verify note ownership before AI calls", () => {
  const src = readSrc("callable.ts");
  assert.ok(src.includes("verifyNoteOwnership"),
    "Note-level callables must verify note ownership");
});

test("callables enforce rate limits", () => {
  const src = readSrc("callable.ts");
  assert.ok(src.includes("checkRateLimit"),
    "All callables must enforce rate limiting");
});

// MARK: - Module Exports

test("index.ts exports all 5 callable functions", () => {
  const src = readSrc("index.ts");
  const callables = [
    "generateChurchNotesContextCallable",
    "generateChurchNotesRecapCallable",
    "extractChurchNotesActionsCallable",
    "generateGrowthTimelineCallable",
    "queryChurchNotesMemoryCallable",
  ];
  for (const callable of callables) {
    assert.ok(src.includes(callable), `index.ts must export ${callable}`);
  }
});

// MARK: - Firestore Rules Contract

test("firestore.rules contains context subcollection rule", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("/context/{contextId}"),
    "firestore.rules must include context subcollection rule");
});

test("firestore.rules contains recaps with editedText-only update", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("/recaps/{recapId}"),
    "firestore.rules must include recaps subcollection rule");
  assert.ok(rules.includes("editedText") && rules.includes("isEdited"),
    "recaps update must only allow editedText and isEdited fields");
});

test("firestore.rules contains actions with approval-only update", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("/actions/{actionId}"),
    "firestore.rules must include actions subcollection rule");
  assert.ok(rules.includes("approvalState"),
    "actions update must only allow approvalState and related fields");
});

test("firestore.rules protects private memory (server-only write)", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("churchNotesMemory"),
    "firestore.rules must include churchNotesMemory rule");
  // Rule must allow owner read but no client write
  const memorySection = rules.slice(rules.indexOf("churchNotesMemory") - 50, rules.indexOf("churchNotesMemory") + 300);
  assert.ok(memorySection.includes("allow read") || memorySection.includes("isOwner"),
    "churchNotesMemory must allow owner to read");
  assert.ok(memorySection.includes("create, update, delete: if false") ||
            memorySection.includes("allow write: if false"),
    "churchNotesMemory must not allow client writes");
});

test("firestore.rules contains noteInsights with membership check", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("noteInsights"),
    "firestore.rules must include noteInsights rule for church group intelligence");
});

test("firestore.rules contains provenance subcollection (server-only)", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("/provenance/{provenanceId}"),
    "firestore.rules must include provenance subcollection rule");
});

test("firestore.rules contains themes subcollection (server-only)", () => {
  const rules = rulesContent();
  assert.ok(rules.includes("/themes/{themeId}"),
    "firestore.rules must include themes subcollection rule");
});

// MARK: - Feature Flag Contract

test("AMENFeatureFlags.swift contains all 10 context engine flags", () => {
  const flagsPath = path.join(__dirname, "..", "..", "AMENAPP", "AMENFeatureFlags.swift");
  const src = fs.readFileSync(flagsPath, "utf8");
  const expectedFlags = [
    "churchNotesContextEngineEnabled",
    "churchNotesSmartMemoryEnabled",
    "churchNotesBereanContextPanelEnabled",
    "churchNotesSermonToActionEnabled",
    "churchNotesGrowthTimelineEnabled",
    "churchNotesSmartRecapEnabled",
    "churchNotesGroupIntelligenceEnabled",
    "churchNotesCommandBarEnabled",
    "churchNotesSmartCaptureEnabled",
    "churchNotesAIProvenanceEnabled",
  ];
  for (const flag of expectedFlags) {
    assert.ok(src.includes(flag), `AMENFeatureFlags.swift must include flag: ${flag}`);
  }
});

test("all context engine flags default to false in production", () => {
  const flagsPath = path.join(__dirname, "..", "..", "AMENAPP", "AMENFeatureFlags.swift");
  const src = fs.readFileSync(flagsPath, "utf8");
  // buildDefaults() should have false for all context engine keys
  assert.ok(src.includes('"church_notes_context_engine_enabled": false as NSObject'),
    "Master context engine flag must default to false");
  assert.ok(src.includes('"church_notes_group_intelligence_enabled": false as NSObject'),
    "Group intelligence flag must default to false (requires verified membership)");
});

test("kill switch flag exists and defaults to false", () => {
  const flagsPath = path.join(__dirname, "..", "..", "AMENAPP", "AMENFeatureFlags.swift");
  const src = fs.readFileSync(flagsPath, "utf8");
  assert.ok(src.includes("churchNotesContextEngineKillSwitch"),
    "Kill switch property must exist in AMENFeatureFlags");
  assert.ok(src.includes('"church_notes_context_engine_kill_switch": false as NSObject'),
    "Kill switch must default to false");
});
