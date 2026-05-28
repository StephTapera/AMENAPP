import { readFileSync } from "fs";
import { resolve } from "path";
import {
    assertFails,
    assertSucceeds,
    initializeTestEnvironment,
    RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

describe("Spaces Firestore rules", () => {
    let testEnv: RulesTestEnvironment;

    beforeAll(async () => {
        testEnv = await initializeTestEnvironment({
            projectId: "amen-spaces-rules-test",
            firestore: {
                rules: readFileSync(resolve(__dirname, "../../../../AMENAPP/firestore.deploy.rules"), "utf8"),
            },
        });
    });

    afterAll(async () => {
        await testEnv.cleanup();
    });

    beforeEach(async () => {
        await testEnv.clearFirestore();
        await testEnv.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await db.doc("spaces/privateSpace").set({
                id: "privateSpace",
                visibility: "private",
                createdBy: "owner",
            });
            await db.doc("spaces/privateSpace/members/member").set({
                userId: "member",
                role: "member",
                roles: ["member"],
                status: "active",
            });
            await db.doc("spaces/privateSpace/members/moderator").set({
                userId: "moderator",
                role: "moderator",
                roles: ["moderator"],
                status: "active",
            });
            await db.doc("spaces/privateSpace/rooms/general/messages/approved").set({
                id: "approved",
                spaceId: "privateSpace",
                guardianStatus: "approved",
                authorId: "member",
            });
            await db.doc("spaces/privateSpace/rooms/general/messages/pending").set({
                id: "pending",
                spaceId: "privateSpace",
                guardianStatus: "pending_review",
                authorId: "member",
            });
            await db.doc("spaces/privateSpace/safetyEvents/safety1").set({
                id: "safety1",
                spaceId: "privateSpace",
            });
            await db.doc("spaces/privateSpace/relationshipGraph/edge1").set({
                id: "edge1",
                spaceId: "privateSpace",
            });
            await db.doc("spaceMemberships/member_privateSpace").set({
                userId: "member",
                spaceId: "privateSpace",
                status: "active",
            });
            await db.doc("spacePosts/post1").set({
                id: "post1",
                spaceId: "privateSpace",
                guardianStatus: "approved",
                createdAt: 1,
            });
            await db.doc("users/member/privateInsights/insight1").set({
                summary: "private",
            });
        });
    });

    it("denies private Space data to non-members", async () => {
        const db = testEnv.authenticatedContext("outsider").firestore();
        await assertFails(db.doc("spaces/privateSpace").get());
        await assertFails(db.doc("spaces/privateSpace/rooms/general/messages/approved").get());
    });

    it("allows members to read approved messages only", async () => {
        const db = testEnv.authenticatedContext("member").firestore();
        await assertSucceeds(db.doc("spaces/privateSpace/rooms/general/messages/approved").get());
        await assertFails(db.doc("spaces/privateSpace/rooms/general/messages/pending").get());
    });

    it("blocks direct client writes to Spaces and legacy Space indexes", async () => {
        const db = testEnv.authenticatedContext("member").firestore();
        await assertFails(db.doc("spaces/privateSpace").set({ name: "unsafe" }, { merge: true }));
        await assertFails(db.doc("spaceMemberships/member_privateSpace").set({ status: "active" }, { merge: true }));
        await assertFails(db.doc("spacePosts/post1").set({ textContent: "unsafe" }, { merge: true }));
    });

    it("keeps private insights and relationship graph server-only", async () => {
        const memberDb = testEnv.authenticatedContext("member").firestore();
        const moderatorDb = testEnv.authenticatedContext("moderator").firestore();
        await assertFails(moderatorDb.doc("users/member/privateInsights/insight1").get());
        await assertFails(memberDb.doc("spaces/privateSpace/relationshipGraph/edge1").get());
    });

    it("allows moderator safety reads and owner-only legacy membership reads", async () => {
        const moderatorDb = testEnv.authenticatedContext("moderator").firestore();
        const memberDb = testEnv.authenticatedContext("member").firestore();
        const outsiderDb = testEnv.authenticatedContext("outsider").firestore();
        await assertSucceeds(moderatorDb.doc("spaces/privateSpace/safetyEvents/safety1").get());
        await assertSucceeds(memberDb.doc("spaceMemberships/member_privateSpace").get());
        await assertFails(outsiderDb.doc("spaceMemberships/member_privateSpace").get());
    });
});
