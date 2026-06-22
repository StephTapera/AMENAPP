import { defineBoolean } from "firebase-functions/params";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

export const MOMENT_REGION = "us-east1";

export type GatherActionKind = "prayLive" | "joinAudio" | "joinDiscussion";

interface Moment {
  id: string;
}

interface GatherRequest {
  moment: Moment;
  action: GatherActionKind;
  requesterId: string;
}

export interface GatherResult {
  momentId: string;
  action: GatherActionKind;
  status: "gated" | "notImplemented";
  reason: "complianceGateRequired" | "flagDisabled" | "v1StubOnly";
}

const momentSystemEnabled = defineBoolean("moment_system_enabled", { default: false });
const gatherLiveEnabled = defineBoolean("gather_live_enabled", { default: false });
const gatherComplianceGateCleared = defineBoolean("gather_compliance_gate_cleared", { default: false });

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function parseGatherRequest(request: CallableRequest<unknown>, action: GatherActionKind): GatherRequest {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  if (!isRecord(request.data) || !isRecord(request.data.moment)) {
    throw new HttpsError("invalid-argument", "moment is required.");
  }

  const momentId = request.data.moment.id;
  if (typeof momentId !== "string" || !momentId.trim()) {
    throw new HttpsError("invalid-argument", "moment.id is required.");
  }

  const requesterId = typeof request.data.requesterId === "string" && request.data.requesterId.trim()
    ? request.data.requesterId
    : uid;

  if (requesterId !== uid) {
    throw new HttpsError("permission-denied", "requesterId must match the authenticated user.");
  }

  return {
    moment: { id: momentId },
    action,
    requesterId,
  };
}

export function makeGatherHandler(action: GatherActionKind) {
  return async (callableRequest: CallableRequest<unknown>): Promise<GatherResult> => {
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
