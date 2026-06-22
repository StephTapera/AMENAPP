"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.selectMomentDeepenRoute = selectMomentDeepenRoute;
const actionModeMap = {
    summarize: "ask",
    crossReference: "discern",
    generatePrayer: "build",
    generateStudyGuide: "build",
    generateDiscussion: "discern",
    generateDevotional: "build",
    saveTo: "build",
};
function selectMomentDeepenRoute(request) {
    return {
        action: request.action,
        selectedMode: actionModeMap[request.action],
        requestedMode: request.bereanMode,
        requiresLivingMemory: request.action === "crossReference",
    };
}
