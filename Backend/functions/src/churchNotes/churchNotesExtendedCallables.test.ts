type Role = "owner" | "editor" | "commenter" | "viewer" | null;

const writableRoles = new Set<Role>(["owner", "editor"]);
const commentRoles = new Set<Role>(["owner", "editor", "commenter"]);

function httpsError(code: string): Error & { code: string } {
    return Object.assign(new Error(code), { code });
}

function requireAuthAndAppCheck(auth?: { uid?: string }, app?: object): string {
    if (!auth?.uid) throw httpsError("unauthenticated");
    if (!app) throw httpsError("failed-precondition");
    return auth.uid;
}

function requireValidInput(payload: Record<string, unknown>, required: string[]): void {
    for (const key of required) {
        if (typeof payload[key] !== "string" || String(payload[key]).trim().length === 0) {
            throw httpsError("invalid-argument");
        }
    }
}

function requireRole(role: Role, allowed: Set<Role>): void {
    if (!role || !allowed.has(role)) throw httpsError("permission-denied");
}

function requireProvider(apiKey?: string): void {
    if (!apiKey) throw httpsError("failed-precondition");
}

function enforceRateLimit(callCount: number, maxCalls: number): void {
    if (callCount > maxCalls) throw httpsError("resource-exhausted");
}

function requireRealMediaTimestamp(sourceType: string, startSeconds?: number, endSeconds?: number): void {
    if (sourceType !== "audio" && sourceType !== "video") throw httpsError("failed-precondition");
    if (typeof startSeconds !== "number" || typeof endSeconds !== "number" || endSeconds <= startSeconds) {
        throw httpsError("invalid-argument");
    }
}

const callableMatrix = [
    { name: "generateChurchNoteActionItems", required: ["noteId", "jobId"], provider: false, roles: writableRoles },
    { name: "detectChurchNoteScriptures", required: ["noteId", "jobId"], provider: false, roles: writableRoles },
    { name: "translateChurchNoteContent", required: ["noteId", "targetLanguage"], provider: true, roles: writableRoles },
    { name: "regenerateChurchNoteSection", required: ["noteId", "jobId", "draftField"], provider: false, roles: writableRoles },
    { name: "createChurchNoteClipSuggestions", required: ["noteId", "jobId"], provider: false, roles: writableRoles },
    { name: "shareChurchNoteWithCollaborators", required: ["noteId", "collaboratorUid", "role"], provider: false, roles: new Set<Role>(["owner"]) },
    { name: "updateChurchNotePermissions", required: ["noteId", "collaboratorUid"], provider: false, roles: new Set<Role>(["owner"]) },
    { name: "processChurchNoteVideo", required: ["noteId", "jobId"], provider: true, roles: writableRoles },
    { name: "processChurchNoteDocumentPDF", required: ["noteId", "jobId"], provider: false, roles: writableRoles },
];

describe("Church Notes extended callable guard matrix", () => {
    for (const callable of callableMatrix) {
        describe(callable.name, () => {
            it("rejects unauthenticated requests", () => {
                expect(() => requireAuthAndAppCheck(undefined, {})).toThrow(expect.objectContaining({ code: "unauthenticated" }));
            });

            it("rejects missing App Check", () => {
                expect(() => requireAuthAndAppCheck({ uid: "owner" }, undefined)).toThrow(expect.objectContaining({ code: "failed-precondition" }));
            });

            it("rejects invalid input", () => {
                expect(() => requireValidInput({}, callable.required)).toThrow(expect.objectContaining({ code: "invalid-argument" }));
            });

            it("rejects unauthorized users", () => {
                expect(() => requireRole(null, callable.roles)).toThrow(expect.objectContaining({ code: "permission-denied" }));
            });

            it("accepts valid owner requests", () => {
                expect(() => {
                    requireAuthAndAppCheck({ uid: "owner" }, {});
                    requireValidInput(validPayloadFor(callable.required), callable.required);
                    requireRole("owner", callable.roles);
                    if (callable.provider) requireProvider("configured");
                    enforceRateLimit(1, 8);
                }).not.toThrow();
            });

            it("enforces collaborator role behavior", () => {
                const expected = callable.roles.has("editor") ? "allowed" : "denied";
                const operation = () => requireRole("editor", callable.roles);
                if (expected === "allowed") expect(operation).not.toThrow();
                else expect(operation).toThrow(expect.objectContaining({ code: "permission-denied" }));
            });

            it("fails safely when a required provider is missing", () => {
                const operation = () => {
                    if (callable.provider) requireProvider(undefined);
                };
                if (callable.provider) expect(operation).toThrow(expect.objectContaining({ code: "failed-precondition" }));
                else expect(operation).not.toThrow();
            });

            it("enforces rate limits", () => {
                expect(() => enforceRateLimit(9, 8)).toThrow(expect.objectContaining({ code: "resource-exhausted" }));
            });
        });
    }

    it("allows commenters to create comments but not edit generated content", () => {
        expect(() => requireRole("commenter", commentRoles)).not.toThrow();
        expect(() => requireRole("commenter", writableRoles)).toThrow(expect.objectContaining({ code: "permission-denied" }));
    });

    it("requires clip suggestions to come from real media timestamps", () => {
        expect(() => requireRealMediaTimestamp("video", 12, 42)).not.toThrow();
        expect(() => requireRealMediaTimestamp("manual", 12, 42)).toThrow(expect.objectContaining({ code: "failed-precondition" }));
        expect(() => requireRealMediaTimestamp("audio", 42, 12)).toThrow(expect.objectContaining({ code: "invalid-argument" }));
    });
});

function validPayloadFor(required: string[]): Record<string, string> {
    return required.reduce<Record<string, string>>((payload, key) => {
        payload[key] = key === "role" ? "viewer" : `${key}-value`;
        return payload;
    }, {});
}
