// index.ts
// Church Notes Context Engine — Module Exports
// All callables are server-owned. Client approves/edits/rejects only.

export {
  generateChurchNotesContextCallable,
  generateChurchNotesRecapCallable,
  extractChurchNotesActionsCallable,
  generateGrowthTimelineCallable,
  queryChurchNotesMemoryCallable,
} from "./callable.js";

// Internal engine exports (for testing and server-to-server calls only)
export { generateChurchNotesContext } from "./churchNotesContextEngine.js";
export { generateChurchNotesMemorySnapshot, loadChurchNotesMemorySnapshot } from "./churchNotesMemoryEngine.js";
export { generateChurchNotesRecap } from "./churchNotesRecapEngine.js";
export { extractChurchNotesActions } from "./churchNotesActionExtractionEngine.js";
export { generateGrowthTimeline, loadGrowthTimeline } from "./churchNotesGrowthTimelineEngine.js";

export type {
  CNContextRequest,
  CNContextResult,
  CNSmartRecap,
  CNMemorySnapshot,
  CNMemoryEntry,
  CNExtractedAction,
  CNGrowthTimelineEntry,
  CNGroupInsight,
  CNProvenanceLabel,
  CNConfidenceLevel,
  CNApprovalState,
  GenerateChurchNotesContextInput,
  GenerateChurchNotesContextOutput,
  GenerateChurchNotesRecapInput,
  GenerateChurchNotesRecapOutput,
  ExtractChurchNotesActionsInput,
  ExtractChurchNotesActionsOutput,
  GenerateGrowthTimelineInput,
  GenerateGrowthTimelineOutput,
  QueryChurchNotesMemoryInput,
  QueryChurchNotesMemoryOutput,
} from "./types.js";
