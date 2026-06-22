import {routeAgentTask} from "./agentTaskRouter";

describe("agent task router", () => {
    it("returns structured task route", () => {
        expect(routeAgentTask("summarize_sermon")).toBe("summarize_sermon");
    });
});
