import * as fs from "fs";
import * as path from "path";
import {
    analyzeMessageSafety,
    summarizeConversationCatchUp,
    translateMessage,
} from "./productionIntelligenceActions";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const adminMock = require("firebase-admin");

const mockDoc = adminMock.__mockDoc;
const mockQuery = adminMock.__mockQuery;

function resetFirestoreMock(data: Record<string, unknown> | undefined = {
    participants: ["user-1"],
    text: "Private message body",
    senderId: "sender-1",
}) {
    jest.clearAllMocks();
    mockDoc.__data = data;
    mockQuery.get = jest.fn(() => Promise.resolve({ docs: [], empty: true }));
    global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: jest.fn().mockResolvedValue({
            content: [{ text: "{\"translatedText\":\"Hola\",\"detectedLanguage\":\"en\"}" }],
        }),
    }) as unknown as typeof fetch;
}

function callableRequest(data: Record<string, unknown>, options?: { auth?: boolean; app?: boolean }) {
    return {
        auth: options?.auth === false ? undefined : { uid: "user-1" },
        app: options?.app === false ? undefined : { appId: "test-app" },
        data,
    };
}

type CallableHandler = (request: ReturnType<typeof callableRequest>) => Promise<unknown>;

function invoke(callable: unknown, request: ReturnType<typeof callableRequest>): Promise<unknown> {
    return (callable as CallableHandler)(request);
}

describe("Amen Messaging production intelligence callables", () => {
    beforeEach(() => {
        resetFirestoreMock();
    });

    test("translateMessage requires auth", async () => {
        await expect(invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "es",
        }, { auth: false }))).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("translateMessage requires App Check", async () => {
        await expect(invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "es",
        }, { app: false }))).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("translateMessage denies non-participants", async () => {
        resetFirestoreMock({ participants: ["someone-else"], text: "Private message body" });

        await expect(invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "es",
        }))).rejects.toMatchObject({ code: "permission-denied" });
    });

    test("translateMessage rejects invalid target language", async () => {
        await expect(invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "not a language",
        }))).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("translateMessage denies restricted messages before model call", async () => {
        resetFirestoreMock({ participants: ["user-1"], text: "Private message body", isRestricted: true });

        await expect(invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "es",
        }))).rejects.toMatchObject({ code: "permission-denied" });
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test("translateMessage returns participant-scoped uncached translation", async () => {
        const result = await invoke(translateMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            targetLanguage: "es",
        }));

        expect(result).toMatchObject({
            translatedText: "Hola",
            detectedLanguage: "en",
            sourceMessageId: "message-1",
            sourceConversationId: "conversation-1",
            aiAssisted: true,
            cached: false,
        });
    });

    test("analyzeMessageSafety returns typed soft warning", async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: jest.fn().mockResolvedValue({
                content: [{ text: "{\"decision\":\"softWarn\",\"reasons\":[\"sensitive_group_share\"],\"userMessage\":\"Review before sharing.\"}" }],
            }),
        }) as unknown as typeof fetch;

        const result = await invoke(analyzeMessageSafety, callableRequest({
            conversationId: "conversation-1",
            text: "This might be sensitive for the group.",
            destination: "group",
        }));

        expect(result).toMatchObject({
            decision: "softWarn",
            reasons: ["sensitive_group_share"],
            message: "Review before sharing.",
            allowSendAnyway: true,
            aiAssisted: true,
        });
    });

    test("analyzeMessageSafety rejects invalid payload", async () => {
        await expect(invoke(analyzeMessageSafety, callableRequest({
            conversationId: "conversation-1",
            text: "",
        }))).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("summarizeConversationCatchUp returns honest empty state without model call", async () => {
        const result = await invoke(summarizeConversationCatchUp, callableRequest({
            conversationId: "conversation-1",
            limit: 20,
        }));

        expect(result).toMatchObject({
            status: "empty",
            aiAssisted: false,
            keyDecisions: [],
            referencedMessageIds: [],
        });
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test("summarizeConversationCatchUp filters anchors to real message IDs", async () => {
        mockQuery.get = jest.fn(() => Promise.resolve({
            docs: [
                { id: "m1", data: () => ({ text: "Can you bring notes?", senderName: "Duncan" }) },
                { id: "m2", data: () => ({ text: "Yes, after 5.", senderName: "Ari" }) },
            ],
            empty: false,
        }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: jest.fn().mockResolvedValue({
                content: [{
                    text: JSON.stringify({
                        keyDecisions: ["Meet after 5."],
                        directAsks: ["Bring notes."],
                        timeDateChanges: ["After 5."],
                        actionItems: ["Bring notes."],
                        mediaShared: [],
                        notesCreated: [],
                        prayerRequests: [],
                        referencedMessageIds: ["m1", "fake-id"],
                    }),
                }],
            }),
        }) as unknown as typeof fetch;

        const result = await invoke(summarizeConversationCatchUp, callableRequest({
            conversationId: "conversation-1",
            limit: 20,
        }));

        expect(result).toMatchObject({
            status: "ready",
            aiAssisted: true,
            keyDecisions: ["Meet after 5."],
            referencedMessageIds: ["m1"],
        });
    });
});

describe("Amen Messaging production intelligence source hygiene", () => {
    test("callables enforce App Check and avoid public cache/logging private content", () => {
        const source = fs.readFileSync(path.resolve(__dirname, "productionIntelligenceActions.ts"), "utf8");

        expect(source).toContain("enforceAppCheck: true");
        expect(source).toContain("requireAuthAndAppCheck");
        expect(source).toContain("cached: false");
        expect(source).not.toMatch(/collection\(["']translation(Cache|s)["']\)/);
        expect(source).not.toMatch(/logger\.(info|warn|error)\([^)]*(body|text|draftText|transcript|mediaUrl|url)/s);
    });
});
