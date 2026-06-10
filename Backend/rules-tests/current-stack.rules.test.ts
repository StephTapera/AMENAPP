import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-current-stack-rules";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const AUTHOR_UID = "author-uid";
const READER_UID = "reader-uid";
const OTHER_UID = "other-uid";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

function dbAs(uid: string, claims: Record<string, unknown> = {}) {
  return testEnv.authenticatedContext(uid, claims).firestore();
}

function dbAnon() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seed(pathValue: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), pathValue), data);
  });
}

function noteShare(visibility: string, data: Record<string, unknown> = {}) {
  return {
    status: "active",
    authorUid: AUTHOR_UID,
    shareConfig: { visibility, ...data },
  };
}

describe("current stack Firestore access matrix", () => {
  it("NoteShare revoked shares return nothing", async () => {
    await seed("noteShares/revoked-share", { ...noteShare("public"), status: "revoked" });

    await assertFails(getDoc(doc(dbAs(READER_UID), "noteShares/revoked-share")));
  });

  it("NoteShare signed-out viewers are blocked", async () => {
    await seed("noteShares/public-share", noteShare("public"));

    await assertFails(getDoc(doc(dbAnon(), "noteShares/public-share")));
  });

  it("NoteShare non-connections are blocked from follower visibility", async () => {
    await seed("noteShares/followers-share", noteShare("followers"));

    await assertFails(getDoc(doc(dbAs(READER_UID), "noteShares/followers-share")));
  });

  it("NoteShare church visibility blocks non-members", async () => {
    await seed("noteShares/church-share", noteShare("church", { churchId: "church-1" }));

    await assertFails(getDoc(doc(dbAs(READER_UID), "noteShares/church-share")));
  });

  it("userSettings are owner-only", async () => {
    await seed(`userSettings/${AUTHOR_UID}`, {
      uid: AUTHOR_UID,
      values: { presenceEnabled: true },
      updatedAt: 1,
    });

    await assertSucceeds(getDoc(doc(dbAs(AUTHOR_UID), `userSettings/${AUTHOR_UID}`)));
    await assertFails(getDoc(doc(dbAs(READER_UID), `userSettings/${AUTHOR_UID}`)));
    await assertFails(getDoc(doc(dbAnon(), `userSettings/${AUTHOR_UID}`)));
  });

  it("presence defaults to nobody except the owner", async () => {
    await seed(`users/${AUTHOR_UID}/sabbath/presence`, {
      resting: true,
      updatedAt: 1,
    });

    await assertSucceeds(getDoc(doc(dbAs(AUTHOR_UID), `users/${AUTHOR_UID}/sabbath/presence`)));
    await assertFails(getDoc(doc(dbAs(READER_UID), `users/${AUTHOR_UID}/sabbath/presence`)));
    await assertFails(getDoc(doc(dbAnon(), `users/${AUTHOR_UID}/sabbath/presence`)));
  });

  it("clients cannot create comment moderation decisions inline", async () => {
    await assertFails(setDoc(doc(dbAs(AUTHOR_UID), "posts/post-1/comments/comment-1"), {
      authorId: AUTHOR_UID,
      body: "This is my comment.",
      moderationDecisionId: "decision-1",
      guardianVerdict: { status: "approved" },
    }));
  });

  it("comment authors cannot mutate moderation decision fields", async () => {
    await seed("posts/post-1/comments/comment-2", {
      authorId: AUTHOR_UID,
      body: "Original",
    });

    await assertSucceeds(updateDoc(doc(dbAs(AUTHOR_UID), "posts/post-1/comments/comment-2"), {
      body: "Edited by author",
    }));
    await assertFails(updateDoc(doc(dbAs(AUTHOR_UID), "posts/post-1/comments/comment-2"), {
      moderationDecisionId: "decision-2",
      moderationStatus: "approved",
    }));
  });

  it("moderationDecisions are Cloud Function owned", async () => {
    await seed("moderationDecisions/decision-1", {
      targetUid: AUTHOR_UID,
      status: "approved",
    });

    await assertSucceeds(getDoc(doc(dbAs(AUTHOR_UID), "moderationDecisions/decision-1")));
    await assertFails(setDoc(doc(dbAs(AUTHOR_UID), "moderationDecisions/decision-2"), {
      targetUid: AUTHOR_UID,
      status: "approved",
    }));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "moderationDecisions/decision-1")));
  });

  it("discernment checks are readable only by their creator", async () => {
    await seed("discernmentChecks/check-1", {
      createdBy: AUTHOR_UID,
      visibility: "shared",
      sourceRef: { threadId: "thread-1" },
      deletedAt: null,
    });

    await assertSucceeds(getDoc(doc(dbAs(AUTHOR_UID), "discernmentChecks/check-1")));
    await assertFails(getDoc(doc(dbAs(READER_UID), "discernmentChecks/check-1")));
  });
});
