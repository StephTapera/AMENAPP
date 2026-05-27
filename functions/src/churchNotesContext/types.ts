// types.ts
// AMEN Church Notes Context Engine — Shared TypeScript Types
//
// These types are shared across all Context Engine backend modules.
// Server-side only: no raw note content is returned to clients without provenance labels.

// MARK: - Provenance

export type CNConfidenceLevel = "confirmed" | "possible" | "needsReview";

export interface CNProvenanceLabel {
  source: string;            // "transcript" | "OCR" | "user note" | "prior notes" | "system"
  confidence: CNConfidenceLevel;
  whySuggested: string;
}

// MARK: - Approval State

export type CNApprovalState = "pending" | "approved" | "edited" | "rejected";

// MARK: - Context Request / Response

export interface CNContextRequest {
  noteId: string;
  userId: string;
  noteText: string;
  sermonTitle?: string;
  sermonSpeaker?: string;
  scriptureReferences?: string[];
  noteHistoryIds?: string[];   // IDs of prior notes to cross-reference
  groupId?: string;
  churchId?: string;
}

export interface CNRelatedScripture {
  id: string;
  reference: string;
  text?: string;
  provenance: CNProvenanceLabel;
}

export interface CNRelatedNote {
  id: string;
  noteId: string;
  title: string;
  sermonTitle?: string;
  connectionSummary: string;
  sharedThemes: string[];
  provenance: CNProvenanceLabel;
}

export interface CNDetectedTheme {
  id: string;
  theme: string;
  occurrenceCount: number;
  isRecurring: boolean;
  exampleQuotes: string[];
  provenance: CNProvenanceLabel;
}

export interface CNPrayerPrompt {
  id: string;
  text: string;
  category: "personal" | "intercession" | "thanksgiving" | "surrender" | "unknown";
  provenance: CNProvenanceLabel;
}

export interface CNReflectionQuestion {
  id: string;
  text: string;
  isPersonal: boolean;
  provenance: CNProvenanceLabel;
}

export interface CNSmallGroupQuestion {
  id: string;
  text: string;
  provenance: CNProvenanceLabel;
}

export interface CNActionSuggestion {
  id: string;
  type: "personalAction" | "prayerItem" | "followUpReminder" | "smallGroupQuestion" | "mentorMessage" | "calendarSuggestion";
  text: string;
  sourceQuote?: string;
  provenance: CNProvenanceLabel;
  approvalState: CNApprovalState;
}

export interface CNContextResult {
  noteId: string;
  userId: string;
  relatedScriptures: CNRelatedScripture[];
  relatedNotes: CNRelatedNote[];
  detectedThemes: CNDetectedTheme[];
  prayerPrompts: CNPrayerPrompt[];
  reflectionQuestions: CNReflectionQuestion[];
  smallGroupQuestions: CNSmallGroupQuestion[];
  actionSuggestions: CNActionSuggestion[];
  generatedAt: FirebaseFirestore.Timestamp | null;
}

// MARK: - Memory Engine

export interface CNMemoryEntry {
  id: string;
  userId: string;
  type: "recurringTheme" | "answeredPrayer" | "repeatedVerse" | "sermonContinuity" | "reflectionCompleted" | "actionFollowedThrough";
  title: string;
  summary: string;
  relatedNoteIds: string[];
  date: FirebaseFirestore.Timestamp | null;
  isPrivate: true;             // always true — server enforces
  provenance: CNProvenanceLabel;
}

export interface CNMemorySnapshot {
  userId: string;
  topThemes: string[];
  repeatedScriptures: string[];
  postureTrend: string;
  recurringPatterns: CNMemoryEntry[];
  lastUpdatedAt: FirebaseFirestore.Timestamp | null;
}

// MARK: - Recap Engine

export interface CNSmartRecap {
  id: string;
  noteId: string;
  userId: string;
  whatStoodOut: string;
  prayerItems: string[];
  nextStep?: string;
  relatedScriptures: string[];
  relatedNoteIds: string[];
  isEdited: boolean;
  editedText?: string;
  generatedAt: FirebaseFirestore.Timestamp | null;
  provenance: CNProvenanceLabel;
}

// MARK: - Action Extraction Engine

export interface CNExtractedAction {
  id: string;
  noteId: string;
  userId: string;
  type: CNActionSuggestion["type"];
  text: string;
  sourceQuote?: string;
  jobId: string;               // ties back to processing job for audit
  approvalState: CNApprovalState;
  provenance: CNProvenanceLabel;
  createdAt: FirebaseFirestore.Timestamp | null;
}

// MARK: - Growth Timeline Engine

export interface CNGrowthTimelineEntry {
  id: string;
  userId: string;
  type: CNMemoryEntry["type"];
  title: string;
  summary: string;
  relatedNoteIds: string[];
  date: FirebaseFirestore.Timestamp | null;
  isPrivate: true;
  provenance: CNProvenanceLabel;
}

// MARK: - Group Intelligence

export interface CNGroupInsight {
  id: string;
  groupId: string;
  churchId?: string;
  topThemes: string[];
  emergingPrayerNeeds: string[];
  recurringQuestions: string[];
  leaderActionItems: string[];
  generatedAt: FirebaseFirestore.Timestamp | null;
  provenance: CNProvenanceLabel;
}

// MARK: - Callable Inputs / Outputs

export interface GenerateChurchNotesContextInput {
  noteId: string;
  noteText: string;
  sermonTitle?: string;
  scriptureReferences?: string[];
  groupId?: string;
  churchId?: string;
}

export interface GenerateChurchNotesContextOutput {
  success: boolean;
  contextId?: string;
  result?: CNContextResult;
  error?: string;
}

export interface GenerateChurchNotesRecapInput {
  noteId: string;
  noteText: string;
}

export interface GenerateChurchNotesRecapOutput {
  success: boolean;
  recapId?: string;
  recap?: CNSmartRecap;
  error?: string;
}

export interface ExtractChurchNotesActionsInput {
  noteId: string;
  jobId: string;
}

export interface ExtractChurchNotesActionsOutput {
  success: boolean;
  actions?: CNExtractedAction[];
  error?: string;
}

export interface GenerateGrowthTimelineInput {
  userId: string;
  noteIds?: string[];
}

export interface GenerateGrowthTimelineOutput {
  success: boolean;
  entries?: CNGrowthTimelineEntry[];
  error?: string;
}

export interface QueryChurchNotesMemoryInput {
  userId: string;
  query?: string;
}

export interface QueryChurchNotesMemoryOutput {
  success: boolean;
  snapshot?: CNMemorySnapshot;
  error?: string;
}

// MARK: - Internal LLM Context

export interface CNLLMContext {
  noteText: string;
  sermonTitle?: string;
  scriptureReferences: string[];
  priorNotesSummary?: string;   // compressed — never raw prior notes
  wordCount: number;
  isTruncated: boolean;
}

export const CN_MAX_INPUT_CHARS = 40_000;
export const CN_MAX_OUTPUT_CHARS = 6_000;
export const CN_SYSTEM_PROMPT_HEADER = `You are a thoughtful assistant helping a person reflect on their church notes.
Speak humbly and reflectively. Never claim divine certainty. Never diagnose the user.
Use language like: "This may connect to...", "A recurring theme appears to be...", "Based on your notes..."
Never say: "God is telling you...", "You always struggle with...", "You should..."
All output must include a source label indicating where the suggestion came from.`;
