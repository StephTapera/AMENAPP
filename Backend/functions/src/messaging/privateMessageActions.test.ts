import * as fs from "fs";
import * as path from "path";
import {
    createMessageReminder,
    createSelahReflectionFromMessage,
    saveMessageToNotes,
} from "./privateMessageActions";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const adminMock = require("firebase-admin");

const mockDoc = adminMock.__mockDoc;

function resetFirestoreMock(data: Record<string, unknown> | undefined = {
    participants: ["user-1"],
    text: "Private message body",
    senderId: "sender-1",
}) {
    jest.clearAllMocks();
    mockDoc.__data = data;
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

describe("Amen Messaging private action callables", () => {
    beforeEach(() => {
        resetFirestoreMock();
    });

    test("saveMessageToNotes requires auth", async () => {
        await expect(invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            sourceSurface: "messaging",
        }, { auth: false }))).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("saveMessageToNotes requires App Check", async () => {
        await expect(invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            sourceSurface: "messaging",
        }, { app: false }))).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("saveMessageToNotes denies non-participants", async () => {
        resetFirestoreMock({ participants: ["someone-else"], text: "Private message body" });

        await expect(invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            sourceSurface: "messaging",
        }))).rejects.toMatchObject({ code: "permission-denied" });
    });

    test("saveMessageToNotes denies deleted or restricted messages", async () => {
        resetFirestoreMock({ participants: ["user-1"], text: "Private message body", isDeleted: true });

        await expect(invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            sourceSurface: "messaging",
        }))).rejects.toMatchObject({ code: "permission-denied" });
    });

    test("saveMessageToNotes creates a private note", async () => {
        const result = await invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            title: "Follow up",
            userEditedBody: "Private user-edited body",
            sourceSurface: "messaging",
        }));

        expect(result).toMatchObject({
            noteId: "mock-doc-id",
            sourceMessageId: "message-1",
            sourceConversationId: "conversation-1",
        });
        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            ownerUid: "user-1",
            visibility: "private",
            aiAssisted: false,
            body: "Private user-edited body",
        }));
    });

    test("createMessageReminder rejects past dueAt", async () => {
        await expect(invoke(createMessageReminder, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            dueAt: Date.now() - 10_000,
        }))).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("createMessageReminder creates a private future reminder", async () => {
        const dueAt = Date.now() + 60_000;
        const result = await invoke(createMessageReminder, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            dueAt,
            title: "Remember this",
        }));

        expect(result).toMatchObject({
            reminderId: "mock-doc-id",
            sourceMessageId: "message-1",
            sourceConversationId: "conversation-1",
        });
        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            ownerUid: "user-1",
            title: "Remember this",
            visibility: "private",
        }));
    });

    test("createSelahReflectionFromMessage creates a private non-AI reflection", async () => {
        const result = await invoke(createSelahReflectionFromMessage, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            reflectionTitle: "Reflection",
            userEditedReflection: "Private reflection",
        }));

        expect(result).toMatchObject({
            reflectionId: "mock-doc-id",
            sourceMessageId: "message-1",
            sourceConversationId: "conversation-1",
        });
        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            ownerUid: "user-1",
            visibility: "private",
            aiAssisted: false,
            text: "Private reflection",
        }));
    });

    test("rate limit exhaustion is enforced before document writes", async () => {
        resetFirestoreMock({ count: 20, windowEnd: Date.now() + 60_000 });

        await expect(invoke(saveMessageToNotes, callableRequest({
            conversationId: "conversation-1",
            messageId: "message-1",
            sourceSurface: "messaging",
        }))).rejects.toMatchObject({ code: "resource-exhausted" });
        expect(mockDoc.set).not.toHaveBeenCalledWith(expect.objectContaining({
            visibility: "private",
        }));
    });
});

describe("Amen Messaging private action source hygiene", () => {
    test("callables enforce App Check and never log message bodies", () => {
        const source = fs.readFileSync(path.resolve(__dirname, "privateMessageActions.ts"), "utf8");

        expect(source).toContain("enforceAppCheck: true");
        expect(source).toContain("requireAuthAndAppCheck");
        expect(source).not.toMatch(/logger\.(info|warn|error)\([^)]*(body|text|userEditedBody|userEditedReflection|noteBody|reflectionText)/s);
    });
});
