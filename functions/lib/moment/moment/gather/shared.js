"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MOMENT_REGION = void 0;
exports.makeGatherHandler = makeGatherHandler;
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
exports.MOMENT_REGION = "us-east1";
const momentSystemEnabled = (0, params_1.defineBoolean)("moment_system_enabled", { default: false });
const gatherLiveEnabled = (0, params_1.defineBoolean)("gather_live_enabled", { default: false });
const gatherComplianceGateCleared = (0, params_1.defineBoolean)("gather_compliance_gate_cleared", { default: false });
function isRecord(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}
function parseGatherRequest(request, action) {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in.");
    }
    if (!isRecord(request.data) || !isRecord(request.data.moment)) {
        throw new https_1.HttpsError("invalid-argument", "moment is required.");
    }
    const momentId = request.data.moment.id;
    if (typeof momentId !== "string" || !momentId.trim()) {
        throw new https_1.HttpsError("invalid-argument", "moment.id is required.");
    }
    const requesterId = typeof request.data.requesterId === "string" && request.data.requesterId.trim()
        ? request.data.requesterId
        : uid;
    if (requesterId !== uid) {
        throw new https_1.HttpsError("permission-denied", "requesterId must match the authenticated user.");
    }
    return {
        moment: { id: momentId },
        action,
        requesterId,
    };
}
function makeGatherHandler(action) {
    return async (callableRequest) => {
        const gatherRequest = parseGatherRequest(callableRequest, action);
        if (!momentSystemEnabled.value() || !gatherLiveEnabled.value()) {
            return {
                momentId: gatherRequest.moment.id,
                action,
                status: "gated",
                reason: "flagDisabled",
            };
        }
        if (!gatherComplianceGateCleared.value()) {
            return {
                momentId: gatherRequest.moment.id,
                action,
                status: "gated",
                reason: "complianceGateRequired",
            };
        }
        return {
            momentId: gatherRequest.moment.id,
            action,
            status: "notImplemented",
            reason: "v1StubOnly",
        };
    };
}
