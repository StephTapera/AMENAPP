const fs = require("fs");
const path = require("path");

describe("actionIntelligenceFunctions", () => {
  test("exports all Action Intelligence callable workflows with App Check and rate limiting", () => {
    const filePath = path.join(__dirname, "..", "actionIntelligenceFunctions.js");
    const source = fs.readFileSync(filePath, "utf8");

    expect(source).toContain("enforceAppCheck: true");
    expect(source).toContain("enforceRateLimit(uid, `action_intelligence_");
    expect(source).toContain("exports.executeAmenAction");
    expect(source).toContain("exports.createAmenInitiative");
    expect(source).toContain("exports.assignAmenVolunteer");
    expect(source).toContain("exports.indexAmenMemoryGraph");
    expect(source).toContain("exports.recordAmenRelationshipSignal");
    expect(source).toContain("exports.writeAmenKnowledgeGraph");
  });

  test("routes capsule verbs into dedicated workflows instead of generic review placeholders", () => {
    const filePath = path.join(__dirname, "..", "actionIntelligenceFunctions.js");
    const source = fs.readFileSync(filePath, "utf8");

    expect(source).toContain("createInitiativeWorkflow");
    expect(source).toContain("volunteerWorkflow");
    expect(source).toContain("memoryWorkflow");
    expect(source).toContain("relationshipWorkflow");
    expect(source).toContain("knowledgeWorkflow");
    expect(source).toContain("draft_pending_leader_review");
    expect(source).not.toContain("generic flow");
    expect(source).not.toContain("proposed for review");
  });
});
