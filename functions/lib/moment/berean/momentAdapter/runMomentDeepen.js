"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runMomentDeepen = runMomentDeepen;
const actionRouting_1 = require("./actionRouting");
const errors_1 = require("./errors");
const validActions = new Set([
    "summarize",
    "crossReference",
    "generatePrayer",
    "generateStudyGuide",
    "generateDiscussion",
    "generateDevotional",
    "saveTo",
]);
const validSaveTargets = new Set([
    "prayerJournal",
    "studyJournal",
    "churchNotes",
    "sermonCollection",
    "savedTeachings",
]);
async function runMomentDeepen(request, dependencies) {
    validateRequest(request);
    validateDependencies(request, dependencies);
    const route = (0, actionRouting_1.selectMomentDeepenRoute)(request);
    const livingMemory = await resolveLivingMemory(request, dependencies, route.requiresLivingMemory);
    const bereanDraft = await dependencies.berean.run({
        request,
        route,
        livingMemory,
    });
    const constitutional = await dependencies.constitutionalIntelligence.review({
        request,
        route,
        draft: bereanDraft,
    });
    const guardian = await dependencies.guardianAegis.review({
        request,
        route,
        constitutional,
    });
    if (!guardian.passed) {
        throw new errors_1.MomentAdapterGuardError(request.action, guardian);
    }
    const result = {
        momentId: request.moment.id,
        action: request.action,
        output: constitutional.output,
        citations: constitutional.citations,
        savedTo: request.action === "saveTo" ? request.saveTarget : undefined,
        guardian,
        createdAt: dependencies.now?.() ?? Date.now(),
    };
    if (request.action === "saveTo") {
        await dependencies.save?.save({ request, result });
    }
    return result;
}
function validateRequest(request) {
    if (!request || typeof request !== "object") {
        throw new errors_1.MomentAdapterValidationError("Moment Deepen request is required.");
    }
    if (!request.moment?.id) {
        throw new errors_1.MomentAdapterValidationError("moment.id is required.");
    }
    if (!request.requesterId) {
        throw new errors_1.MomentAdapterValidationError("requesterId is required.");
    }
    if (!validActions.has(request.action)) {
        throw new errors_1.MomentAdapterValidationError(`Unsupported Moment Deepen action: ${request.action}`);
    }
    if (request.action === "saveTo") {
        if (!request.saveTarget || !validSaveTargets.has(request.saveTarget)) {
            throw new errors_1.MomentAdapterValidationError("saveTarget is required for saveTo.");
        }
    }
}
function validateDependencies(request, dependencies) {
    if (!dependencies?.berean) {
        throw new errors_1.MomentAdapterDependencyError("berean", request.action);
    }
    if (!dependencies.constitutionalIntelligence) {
        throw new errors_1.MomentAdapterDependencyError("constitutionalIntelligence", request.action);
    }
    if (!dependencies.guardianAegis) {
        throw new errors_1.MomentAdapterDependencyError("guardianAegis", request.action);
    }
    if (request.action === "saveTo" && !dependencies.save) {
        throw new errors_1.MomentAdapterDependencyError("save", request.action);
    }
}
async function resolveLivingMemory(request, dependencies, required) {
    if (!required) {
        return [];
    }
    if (!dependencies.livingMemory) {
        throw new errors_1.MomentAdapterDependencyError("livingMemory", request.action, "crossReference requires a Living Memory/Pinecone adapter dependency.");
    }
    return dependencies.livingMemory.crossReference({
        requesterId: request.requesterId,
        moment: request.moment,
        action: "crossReference",
        locale: request.locale,
    });
}
