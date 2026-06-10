const mockShareGet = jest.fn();
const mockRateLimitGet = jest.fn();
const mockRunTransaction = jest.fn();

jest.mock("firebase-admin", () => {
    const mockFirestore = jest.fn(() => ({
        collection: jest.fn((collectionName: string) => {
            if (collectionName === "rateLimits") {
                return {
                    doc: jest.fn(() => ({ path: "rateLimits/noteShareGetViewerPayload:viewer:1" })),
                };
            }
            if (collectionName === "noteShares") {
                return {
                    doc: jest.fn(() => ({
                        get: mockShareGet,
                        collection: jest.fn(),
                    })),
                };
            }
            return {
                doc: jest.fn(() => ({ get: jest.fn() })),
            };
        }),
        runTransaction: mockRunTransaction,
    }));

    return {
        firestore: Object.assign(mockFirestore, {
            FieldValue: {
                serverTimestamp: jest.fn(() => "serverTimestamp"),
            },
            Timestamp: {
                fromMillis: jest.fn((millis: number) => ({ millis })),
            },
        }),
    };
});

jest.mock("firebase-functions/v2/https", () => {
    class MockHttpsError extends Error {
        code: string;

        constructor(code: string, message: string) {
            super(message);
            this.code = code;
        }
    }

    return {
        HttpsError: MockHttpsError,
        onCall: jest.fn((options, handler) => ({ options, run: handler })),
    };
});

jest.mock("../thinkFirst/validator", () => ({
    validateThinkFirst: jest.fn(() => ({
        action: "allow",
        maxSeverity: "none",
        categories: [],
    })),
}));

import { noteShareGetViewerPayload } from "../noteShare";

describe("noteShareGetViewerPayload", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockRateLimitGet.mockResolvedValue({ data: () => ({ count: 0 }) });
        mockRunTransaction.mockImplementation(async (callback: (tx: unknown) => Promise<void>) => callback({
            get: mockRateLimitGet,
            set: jest.fn(),
        }));
    });

    it("requires Auth and App Check on the viewer callable", () => {
        const callable = noteShareGetViewerPayload as unknown as { options: { enforceAppCheck: boolean } };

        expect(callable.options.enforceAppCheck).toBe(true);
    });

    it("returns no viewer payload for a revoked share", async () => {
        mockShareGet.mockResolvedValue({
            exists: true,
            data: () => ({
                noteId: "note-1",
                authorUid: "author",
                status: "revoked",
                linkToken: null,
                shareConfig: {
                    visibility: "link",
                    allowAmens: true,
                    allowComments: "off",
                    allowReshare: false,
                    showCounts: false,
                    authorPrivateAmenList: true,
                    attribution: "full",
                    watermarkOnExport: true,
                },
            }),
        });

        const callable = noteShareGetViewerPayload as unknown as {
            run: (request: Record<string, unknown>) => Promise<Record<string, unknown>>;
        };

        await expect(callable.run({
            app: { appId: "test-app" },
            auth: { uid: "viewer" },
            data: { shareId: "share-revoked", linkToken: "old-token" },
        })).rejects.toMatchObject({
            code: "permission-denied",
            message: "You do not have access to this shared note.",
        });
    });
});
