// index.ts
// AMEN Spaces Ambient Intelligence — Module Exports
//
// Re-exports all Cloud Functions callables and scheduled jobs for registration in functions/index.js

export {
  getAmbientSignals,
  dismissAmbientSignal,
  getMemoryNodes,
  dismissMemoryNode,
  getSemanticPins,
  createUserPin,
  dismissPin,
  getSpiritualContinuity,
  recordSelahMoment,
  triggerSpaceIntelligence,
  scheduledPinScoreEvolution,
  scheduledPinTypeEvolution,
  scheduledMemoryExpiry,
  scheduledSignalCleanup,
} from "./callable";

// Engine exports (for use in other backend modules)
export { generateAmbientSignals, cleanupOldSignals } from "./ambientIntelligenceEngine";
export {
  persistMemoryNode, getSpaceMemoryNodes, getUserSpaceMemory,
  isDuplicateMemory, upsertSpiritualContinuity, expireOldMemoryNodes,
} from "./persistentMemoryGraph";
export {
  recalculatePinScores, evolvePins, createIntelligentPin,
} from "./semanticPinningEngine";
export {
  AmenSpaceType, MemoryLayer, PinType, AmbientSignalType,
  aiInferenceAllowed, AI_INFERENCE_BLOCKED_TYPES, SERVER_PIN_TYPES,
} from "./types";
