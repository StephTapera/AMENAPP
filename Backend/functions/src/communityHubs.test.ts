import {
    resolveCommunityObject,
    getObjectHub,
    recordObjectInteraction,
    muteObjectHub,
    reportHubContent,
    getRelatedObjectHubs,
    indexPostIntoHub,
} from "./communityHubs";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const admin = require("firebase-admin");
const { __mockCollection, __mockDoc, __mockQuery } = admin;

type Handler = (request: Record<string, unknown>) => Promise<any>;

type MockDoc = {
    id: string;
    exists: boolean;
    data: Record<string, unknown>;
};

const docs = new Map<string, MockDoc>();

function key(path: string): string { return path; }
function idKey(id: string): string { return `__id__/${id}`; }

function setDoc(path: string, data: Record<string, unknown>, id: string): void {
    const value = { id, exists: true, data };
    docs.set(key(path), value);
    docs.set(idKey(id), value);
}

function noDoc(path: string, id: string): void {
    const value = { id, exists: false, data: {} };
    docs.set(key(path), value);
    docs.set(idKey(id), value);
}

function authed(data: Record<string, unknown> = {}): Record<string, unknown> {
    return { auth: { uid: "user-1" }, app: { appId: "app" }, data };
}

function unauthed(data: Record<string, unknown> = {}): Record<string, unknown> {
    return { auth: undefined, app: { appId: "app" }, data };
}

beforeEach(() => {
    jest.clearAllMocks();
    docs.clear();

    __mockDoc.collection.mockImplementation((name: string) => {
        if (name === "members") {
            return {
                doc: jest.fn((id: string) => {
                    const _path = `communityHubs/hub-1/members/${id}`;
                    return {
                        set: jest.fn(async () => undefined),
                        get: jest.fn(async () => ({ exists: false, data: () => undefined })),
                    };
                }),
            };
        }
        return __mockCollection;
    });

    __mockCollection.doc.mockImplementation((id?: string) => {
        const forcedId = id ?? "mock-id";
        const basePath = (global as any).__collectionPath as string;
        const path = `${basePath}/${forcedId}`;
        return {
            id: forcedId,
            get: jest.fn(async () => {
                const d = docs.get(path) ?? docs.get(idKey(forcedId)) ?? { id: forcedId, exists: false, data: {} };
                return { exists: d.exists, id: d.id, data: () => d.data };
            }),
            set: jest.fn(async () => undefined),
            update: jest.fn(async () => undefined),
            delete: jest.fn(async () => undefined),
            collection: jest.fn((sub: string) => ({
                doc: jest.fn((_subId: string) => ({
                    set: jest.fn(async () => undefined),
                    get: jest.fn(async () => ({ exists: false, data: () => undefined })),
                })),
                get: jest.fn(async () => {
                    const mocked = await __mockCollection.get();
                    if (Array.isArray(mocked?.docs) && mocked.docs.length > 0) {
                        return mocked;
                    }
                    const prefix = `${path}/${sub}/`;
                    const subDocs = Array.from(docs.entries())
                        .filter(([k, d]) => k.startsWith(prefix) && d.exists)
                        .map(([k, d]) => ({
                            id: d.id,
                            data: () => d.data,
                            ref: { path: k },
                        }));
                    return { docs: subDocs, empty: subDocs.length === 0 };
                }),
            })),
        };
    });

    __mockCollection.add.mockResolvedValue({ id: "report-1" });

    __mockCollection.where.mockImplementation(() => __mockQuery);
    __mockCollection.orderBy.mockImplementation(() => __mockQuery);
    __mockCollection.limit.mockImplementation(() => __mockQuery);

    __mockQuery.where.mockImplementation(() => __mockQuery);
    __mockQuery.orderBy.mockImplementation(() => __mockQuery);
    __mockQuery.limit.mockImplementation(() => __mockQuery);

    __mockQuery.get.mockResolvedValue({ docs: [], empty: true });

    const firestore = admin.firestore();
    firestore.collection.mockImplementation((path: string) => {
        (global as any).__collectionPath = path;
        return __mockCollection;
    });
});

describe("communityHubs auth guards", () => {
    test("resolveCommunityObject requires auth", async () => {
        await expect((resolveCommunityObject as unknown as Handler)(unauthed({ url: "https://a" })))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("getObjectHub requires auth", async () => {
        await expect((getObjectHub as unknown as Handler)(unauthed({ canonicalObjectId: "c1" })))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("recordObjectInteraction requires auth", async () => {
        await expect((recordObjectInteraction as unknown as Handler)(unauthed({ hubId: "h1", interactionType: "saved" })))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("muteObjectHub requires auth", async () => {
        await expect((muteObjectHub as unknown as Handler)(unauthed({ hubId: "h1" })))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("reportHubContent requires auth", async () => {
        await expect((reportHubContent as unknown as Handler)(unauthed({ hubId: "h1", reason: "spam" })))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });
});

describe("communityHubs safety behavior", () => {
    test("canonical matching does not auto-merge low-confidence objects", async () => {
        __mockQuery.get.mockResolvedValue({ docs: [], empty: true });
        const out = await (resolveCommunityObject as unknown as Handler)(authed({ url: "https://new.example", title: "Fresh" }));
        expect(out.canonicalObjectId).toBeTruthy();
    });

    test("explicit content is returned with explicitContentState", async () => {
        setDoc("canonicalObjects/c1", { hubId: "hub-1", contentCategory: "music", explicitContentState: "explicit" }, "c1");
        setDoc("communityHubs/hub-1", { privacyLevel: "public", safetyStatus: "approved", explicitContentState: "explicit" }, "hub-1");
        __mockQuery.get.mockResolvedValue({ docs: [], empty: true });

        const out = await (getObjectHub as unknown as Handler)(authed({ canonicalObjectId: "c1" }));
        expect(out.hub.explicitContentState).toBe("explicit");
        expect(out.canonicalObject.explicitContentState).toBe("explicit");
    });

    test("aggregate output does not expose private user identity fields", async () => {
        setDoc("canonicalObjects/c1", { hubId: "hub-1", contentCategory: "music" }, "c1");
        setDoc("communityHubs/hub-1", { privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean", totalMembers: 2 }, "hub-1");
        const out = await (getObjectHub as unknown as Handler)(authed({ canonicalObjectId: "c1" }));
        expect(out.hub.reporterUid).toBeUndefined();
        expect(out.hub.userId).toBeUndefined();
    });

    test("reportHubContent writes expected report shape", async () => {
        setDoc("communityHubs/hub-1", { privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean" }, "hub-1");
        const out = await (reportHubContent as unknown as Handler)(authed({ hubId: "hub-1", reason: "spam" }));
        expect(out.ok).toBe(true);
        expect(__mockCollection.add).toHaveBeenCalled();
        expect(__mockCollection.add.mock.calls[0][0]).toEqual(expect.objectContaining({
            hubId: "hub-1",
            reporterUid: "user-1",
            reason: "spam",
            status: "pending",
            source: "objectHub",
        }));
    });

    test("recordObjectInteraction respects allowed interaction types", async () => {
        setDoc("communityHubs/hub-1", { privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean" }, "hub-1");
        await expect((recordObjectInteraction as unknown as Handler)(authed({ hubId: "hub-1", interactionType: "hacked" })))
            .rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("invalid hub/object ids are rejected safely", async () => {
        noDoc("canonicalObjects/missing", "missing");
        await expect((getObjectHub as unknown as Handler)(authed({ canonicalObjectId: "missing" })))
            .rejects.toMatchObject({ code: "not-found" });

        noDoc("communityHubs/missing-hub", "missing-hub");
        await expect((muteObjectHub as unknown as Handler)(authed({ hubId: "missing-hub" })))
            .rejects.toMatchObject({ code: "not-found" });
    });

    test("indexPostIntoHub skips blocked/private posts", async () => {
        const blockedEvent = {
            data: {
                data: () => ({
                    visibility: "private",
                    smartAttachment: { canonicalObjectId: "c1" },
                }),
            },
        };

        await (indexPostIntoHub as unknown as (event: Record<string, unknown>) => Promise<void>)(blockedEvent);
        expect(__mockCollection.doc).not.toHaveBeenCalledWith("c1");
    });

    test("indexPostIntoHub writes aggregate-safe communityHubPreview", async () => {
        setDoc("canonicalObjects/c1", {
            hubId: "hub-1",
            objectType: "song",
            title: "Grace Song",
            canonicalUrl: "https://example.com/song",
            privacyLevel: "public",
            safetyStatus: "approved",
            explicitContentState: "clean",
        }, "c1");
        setDoc("communityHubs/hub-1", {
            privacyLevel: "public",
            safetyStatus: "approved",
            explicitContentState: "clean",
            totalPostCount: 12,
            totalMembers: 8,
        }, "hub-1");

        const update = jest.fn(async () => undefined);
        const safeEvent = {
            data: {
                data: () => ({
                    visibility: "public",
                    smartAttachment: { canonicalObjectId: "c1" },
                    explicitContentState: "clean",
                    safetyStatus: "approved",
                }),
                ref: { update },
            },
        };

        await (indexPostIntoHub as unknown as (event: Record<string, unknown>) => Promise<void>)(safeEvent);
        expect(update).toHaveBeenCalledWith(expect.objectContaining({
            communityHubPreview: expect.objectContaining({
                hubId: "hub-1",
                canonicalObjectId: "c1",
                aggregateText: "12 public posts",
                actionText: "Song Hub",
            }),
        }));
        const calls = update.mock.calls as unknown as Array<[Record<string, unknown>]>;
        expect(calls.length).toBeGreaterThan(0);
        const firstPayload = (calls[0]?.[0] ?? {}) as { communityHubPreview?: Record<string, unknown> };
        const preview = firstPayload.communityHubPreview ?? {};
        expect(preview.reporterUid).toBeUndefined();
        expect(preview.userId).toBeUndefined();
    });

    test("indexPostIntoHub does not write preview for blocked hub", async () => {
        setDoc("canonicalObjects/c1", {
            hubId: "hub-1",
            objectType: "song",
            title: "Grace Song",
            privacyLevel: "public",
            safetyStatus: "approved",
            explicitContentState: "clean",
        }, "c1");
        setDoc("communityHubs/hub-1", {
            privacyLevel: "public",
            safetyStatus: "blocked",
            explicitContentState: "blocked",
            totalPostCount: 4,
        }, "hub-1");

        const update = jest.fn(async () => undefined);
        const blockedHubEvent = {
            data: {
                data: () => ({
                    visibility: "public",
                    smartAttachment: { canonicalObjectId: "c1" },
                    explicitContentState: "clean",
                    safetyStatus: "approved",
                }),
                ref: { update },
            },
        };

        await (indexPostIntoHub as unknown as (event: Record<string, unknown>) => Promise<void>)(blockedHubEvent);
        expect(update).not.toHaveBeenCalled();
    });

    test("getRelatedObjectHubs returns safe public hubs only", async () => {
        setDoc("canonicalObjects/c1", { contentCategory: "music", hubId: "hub-1" }, "c1");

        const docsOut = [
            { id: "hub-1", data: () => ({ privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean" }) },
            { id: "hub-2", data: () => ({ privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean" }) },
            { id: "hub-3", data: () => ({ privacyLevel: "public", safetyStatus: "blocked", explicitContentState: "blocked" }) },
        ];
        __mockQuery.get.mockResolvedValueOnce({ docs: docsOut, empty: false });

        const out = await (getRelatedObjectHubs as unknown as Handler)(authed({ canonicalObjectId: "c1", limit: 8 }));
        expect(out.hubs.map((h: any) => h.id)).toEqual(["hub-2"]);
    });

    test("muted hub is filtered from related hub recommendations", async () => {
        setDoc("canonicalObjects/c1", { contentCategory: "music", hubId: "hub-1" }, "c1");
        const docsOut = [
            { id: "hub-2", data: () => ({ privacyLevel: "public", safetyStatus: "approved", explicitContentState: "clean" }) },
        ];
        __mockQuery.get.mockResolvedValueOnce({ docs: docsOut, empty: false });
        setDoc("users/user-1/mutedHubs/hub-2", { hubId: "hub-2", userId: "user-1" }, "hub-2");
        __mockCollection.get.mockResolvedValueOnce({ docs: [{ id: "hub-2" }], empty: false });

        const out = await (getRelatedObjectHubs as unknown as Handler)(authed({ canonicalObjectId: "c1" }));
        expect(out.hubs).toHaveLength(0);
    });
});
