import {
  MomentBereanMode,
  MomentDeepenAction,
  MomentDeepenRequest,
  MomentDeepenRoute,
} from "./types";

const actionModeMap: Record<MomentDeepenAction, MomentBereanMode> = {
  summarize: "ask",
  crossReference: "discern",
  generatePrayer: "build",
  generateStudyGuide: "build",
  generateDiscussion: "discern",
  generateDevotional: "build",
  saveTo: "build",
};

export function selectMomentDeepenRoute(request: MomentDeepenRequest): MomentDeepenRoute {
  return {
    action: request.action,
    selectedMode: actionModeMap[request.action],
    requestedMode: request.bereanMode,
    requiresLivingMemory: request.action === "crossReference",
  };
}
