import {validateAgentTaskPayload} from "./agentGuardrails";

describe("agent guardrails", () => {
    it("blocks unsafe fabricated church announcement content", () => {
        const result = validateAgentTaskPayload("draft_announcement", "This is a fake church announcement");
        expect(result.ok).toBe(false);
    });

    it("allows normal content", () => {
        const result = validateAgentTaskPayload("create_post", "Please summarize this reflection");
        expect(result.ok).toBe(true);
    });
});
