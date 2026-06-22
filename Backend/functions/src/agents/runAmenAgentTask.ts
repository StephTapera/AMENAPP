import {onCall, HttpsError} from "firebase-functions/v2/https";
import {enforceAmenGuards, requireAuthAndAppCheck, saveGeneratedDraft} from "../amenAI/common";
import {AmenAgentTaskType, routeAgentTask} from "./agentTaskRouter";
import {validateAgentTaskPayload} from "./agentGuardrails";
import {logAgentEvent} from "./agentObservability";
import {formatAgentResult} from "./agentResultFormatter";

export const runAmenAgentTask = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceAmenGuards({uid, taskType: "agent_workflow", featureFlag: "amenAgentWorkflowsEnabled", killSwitch: "amenAgentWorkflowKillSwitch"});

    const taskType = String(request.data?.taskType ?? "") as AmenAgentTaskType;
    const content = String(request.data?.content ?? "");
    const validity = validateAgentTaskPayload(taskType, content);
    if (!validity.ok) {
        await logAgentEvent("amen_agent_task_blocked", {uid, taskType, reason: validity.reason});
        throw new HttpsError("failed-precondition", "Task blocked by guardrails.");
    }

    const routed = routeAgentTask(taskType);
    const {draftId} = await saveGeneratedDraft({uid, sourceSurface: "creator_kit", taskType: routed, outputType: "text", body: content});
    await logAgentEvent("amen_agent_task_completed", {uid, taskType: routed, draftId});
    return formatAgentResult(draftId);
});
