"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MOMENT_REGION = void 0;
exports.makeDeepenHandler = makeDeepenHandler;
exports.configureMomentDeepenDependencies = configureMomentDeepenDependencies;
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
exports.MOMENT_REGION = "us-east1";
const momentSystemEnabled = (0, params_1.defineBoolean)("moment_system_enabled", { default: false });
const deepenActionsEnabled = (0, params_1.defineBoolean)("deepen_actions_enabled", { default: false });
let momentDeepenDependencies;
const validMomentTypes = new Set([
    "prayer",
    "scripture",
    "sermon",
    "event",
    "creator",
    "study",
    "mission",
    "thread",
]);
const validTemporalStates = new Set(["upcoming", "live", "recap", "evergreen"]);
const validBereanModes = new Set(["ask", "discern", "build"]);
const validSaveTargets = new Set([
    "prayerJournal",
    "studyJournal",
    "churchNotes",
    "sermonCollection",
    "savedTeachings",
]);
function isRecord(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}
function parseMoment(value) {
    if (!isRecord(value)) {
        throw new https_1.HttpsError("invalid-argument", "moment is required.");
    }
    const { id, type, temporalState, refId, ownerId, createdAt } = value;
    if (typeof id !== "string" || !id.trim()) {
        throw new https_1.HttpsError("invalid-argument", "moment.id is required.");
    }
    if (typeof type !== "string" || !validMomentTypes.has(type)) {
        throw new https_1.HttpsError("invalid-argument", "moment.type is invalid.");
    }
    if (typeof temporalState !== "string" || !validTemporalStates.has(temporalState)) {
        throw new https_1.HttpsError("invalid-argument", "moment.temporalState is invalid.");
    }
    if (typeof refId !== "string" || !refId.trim()) {
        throw new https_1.HttpsError("invalid-argument", "moment.refId is required.");
    }
    if (typeof ownerId !== "string" || !ownerId.trim()) {
        throw new https_1.HttpsError("invalid-argument", "moment.ownerId is required.");
    }
    if (typeof createdAt !== "number" || !Number.isFinite(createdAt)) {
        throw new https_1.HttpsError("invalid-argument", "moment.createdAt is required.");
    }
    return {
        id,
        type: type,
        temporalState: temporalState,
        refId,
        ownerId,
        createdAt,
    };
}
function parseDeepenRequest(request, action) {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!isRecord(request.data)) {
        throw new https_1.HttpsError("invalid-argument", "request body is required.");
    }
    const moment = parseMoment(request.data.moment);
    const requesterId = typeof request.data.requesterId === "string" && request.data.requesterId.trim()
        ? request.data.requesterId
        : uid;
    if (requesterId !== uid) {
        throw new https_1.HttpsError("permission-denied", "requesterId must match the authenticated user.");
    }
    const bereanMode = typeof request.data.bereanMode === "string" && validBereanModes.has(request.data.bereanMode)
        ? request.data.bereanMode
        : "ask";
    const saveTarget = request.data.saveTarget;
    if (saveTarget !== undefined && (typeof saveTarget !== "string" || !validSaveTargets.has(saveTarget))) {
        throw new https_1.HttpsError("invalid-argument", "saveTarget is invalid.");
    }
    const locale = request.data.locale;
    if (locale !== undefined && typeof locale !== "string") {
        throw new https_1.HttpsError("invalid-argument", "locale must be a string.");
    }
    return {
        moment,
        action,
        requesterId,
        bereanMode,
        saveTarget: saveTarget,
        locale: locale,
    };
}
function disabledDeepenResult(request) {
    return {
        momentId: request.moment.id,
        action: request.action,
        output: "",
        citations: [],
        savedTo: request.action === "saveTo" ? request.saveTarget : undefined,
        guardian: {
            passed: false,
            policyVersion: "moment-v1",
            reason: "flagDisabled",
        },
        createdAt: Date.now(),
    };
}
function adapterFromModule(moduleExports) {
    if (!isRecord(moduleExports)) {
        return undefined;
    }
    const adapter = moduleExports.momentAdapter;
    if (isRecord(adapter) && typeof adapter.runMomentDeepen === "function") {
        return adapter;
    }
    if (typeof moduleExports.runMomentDeepen === "function") {
        return { runMomentDeepen: moduleExports.runMomentDeepen };
    }
    return undefined;
}
function loadMomentAdapter() {
    try {
        // A3 owns this module. Keep only the narrow call expectation here.
        return adapterFromModule(require("../../berean/momentAdapter"));
    }
    catch (error) {
        const code = isRecord(error) ? error.code : undefined;
        if (code === "MODULE_NOT_FOUND") {
            return undefined;
        }
        throw error;
    }
}
function makeDeepenHandler(action) {
    return async (callableRequest) => {
        const deepenRequest = parseDeepenRequest(callableRequest, action);
        if (!momentSystemEnabled.value() || !deepenActionsEnabled.value()) {
            return disabledDeepenResult(deepenRequest);
        }
        const adapter = loadMomentAdapter();
        if (!adapter) {
            throw new https_1.HttpsError("failed-precondition", "Moment Deepen adapter is not available.");
        }
        if (!momentDeepenDependencies) {
            throw new https_1.HttpsError("failed-precondition", "Moment Deepen dependencies are not wired.");
        }
        try {
            return await adapter.runMomentDeepen(deepenRequest, momentDeepenDependencies);
        }
        catch (error) {
            throw mapMomentAdapterError(error);
        }
    };
}
function configureMomentDeepenDependencies(dependencies) {
    momentDeepenDependencies = dependencies;
}
function mapMomentAdapterError(error) {
    if (error instanceof https_1.HttpsError) {
        return error;
    }
    if (isRecord(error)) {
        const code = error.code;
        const message = typeof error.message === "string" ? error.message : "Moment Deepen adapter failed.";
        if (code === "moment-adapter/invalid-request") {
            return new https_1.HttpsError("invalid-argument", message);
        }
        if (code === "moment-adapter/dependency-required") {
            return new https_1.HttpsError("failed-precondition", message);
        }
        if (code === "moment-adapter/guardian-blocked") {
            return new https_1.HttpsError("failed-precondition", message);
        }
    }
    return new https_1.HttpsError("internal", "Moment Deepen adapter failed.");
}
