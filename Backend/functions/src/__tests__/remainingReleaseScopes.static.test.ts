import fs from "fs";
import path from "path";

const srcRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(srcRoot, "../../..");

function read(rel: string): string {
    return fs.readFileSync(path.join(repoRoot, rel), "utf8");
}

describe("remaining release scopes hardening", () => {
    test("Berean streaming endpoint enforces Auth, App Check, entitlement, quota, and output validation", () => {
        const stream = read("functions/src/bereanChatProxyStream.ts");
        expect(stream).toContain("verifyToken(appCheckToken)");
        expect(stream).toContain("verifyIdToken");
        expect(stream).toContain("getBereanTierForUser");
        expect(stream).toContain("resolveEntitledModel");
        expect(stream).toContain("streamRequestCount");
        expect(stream).toContain("validateRawTextOutput");
        expect(stream).not.toContain("res.write(`data: ${JSON.stringify({delta: text})}");
    });

    test("legacy client-supplied Church Notes AI draft callable is disabled", () => {
        const legacyDraft = read("functions/src/churchNotes/createChurchNotesAIDraft.ts");
        expect(legacyDraft).toContain("Legacy client-supplied Church Notes AI drafts are disabled");
        expect(legacyDraft).not.toContain("generatedText: String(request.data?.generatedText");
    });

    test("post reactions are server-authoritative callables with Auth and App Check", () => {
        const reactions = read("functions/src/postReactions.ts");
        const index = read("functions/src/index.ts");
        expect(index).toContain("export * from \"./postReactions\"");
        expect(reactions).toContain("enforceAppCheck: true");
        expect(reactions).toContain("requireAuthAndAppCheck");
        expect(reactions).toContain("runTransaction");
        expect(reactions).toContain("flaggedForReview");
        expect(reactions).toContain("removed");
        expect(reactions).toContain("assertNotBlocked");
        expect(reactions).toContain("FieldValue.serverTimestamp()");
    });
});
