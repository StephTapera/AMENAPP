import {AmenAgentTaskType} from "./agentTaskRouter";

export function validateAgentTaskPayload(taskType: AmenAgentTaskType, content: string): {ok: boolean; reason?: string} {
    if (!content.trim()) return {ok: false, reason: "empty_input"};
    if (/fake church announcement|fabricated scripture/i.test(content)) return {ok: false, reason: "unsafe_input"};
    return {ok: true};
}
