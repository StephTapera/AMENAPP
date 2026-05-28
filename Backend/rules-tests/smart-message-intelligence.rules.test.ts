import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import fs from "fs";
import path from "path";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "amen-smart-message-rules",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"),
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
    await setDoc(doc(db, "spaces/space1"), { memberIds: ["member1"] });
    await setDoc(doc(db, "spaces/space1/members/member1"), { status: "active" });
    await setDoc(doc(db, "spaces/space1/smartThreads/thread1/insights/insight1"), { summary: "Server summary" });
    await setDoc(doc(db, "spaces/space1/smartThreads/thread1/entities/entity1"), { type: "topic" });
    await setDoc(doc(db, "spaces/space1/semanticIndex/items/items/item1"), { tokens: ["romans"] });
    await setDoc(doc(db, "spaces/space1/knowledgeGraph/nodes/nodes/node1"), { title: "Romans" });
    await setDoc(doc(db, "users/owner1/smartMessageMemory/node1"), { title: "Private" });
  });
});

describe("Amen Smart Message Intelligence Firestore rules", () => {
  it("denies unauthenticated reads", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "spaces/space1/smartThreads/thread1/insights/insight1")));
  });

  it("denies non-member reads", async () => {
    const db = testEnv.authenticatedContext("outsider").firestore();
    await assertFails(getDoc(doc(db, "spaces/space1/smartThreads/thread1/insights/insight1")));
  });

  it("allows member reads", async () => {
    const db = testEnv.authenticatedContext("member1").firestore();
    await assertSucceeds(getDoc(doc(db, "spaces/space1/smartThreads/thread1/insights/insight1")));
  });

  it("denies client generated insight writes", async () => {
    const db = testEnv.authenticatedContext("member1").firestore();
    await assertFails(setDoc(doc(db, "spaces/space1/smartThreads/thread1/insights/newInsight"), { summary: "client" }));
  });

  it("enforces owner-only user memory", async () => {
    const ownerDb = testEnv.authenticatedContext("owner1").firestore();
    const otherDb = testEnv.authenticatedContext("member1").firestore();
    await assertSucceeds(getDoc(doc(ownerDb, "users/owner1/smartMessageMemory/node1")));
    await assertFails(getDoc(doc(otherDb, "users/owner1/smartMessageMemory/node1")));
  });

  it("allows prayer request creation for members only", async () => {
    const memberDb = testEnv.authenticatedContext("member1").firestore();
    const outsiderDb = testEnv.authenticatedContext("outsider").firestore();
    const data = {
      createdBy: "member1",
      body: "Please pray",
      visibility: "space",
      category: "general prayer",
      sourceMessageId: "m1",
      threadId: "thread1",
      status: "open",
      createdAt: Date.now(),
    };
    await assertSucceeds(setDoc(doc(memberDb, "spaces/space1/prayerRequests/request1"), data));
    await assertFails(setDoc(doc(outsiderDb, "spaces/space1/prayerRequests/request2"), { ...data, createdBy: "outsider" }));
  });

  it("denies semantic index and knowledge graph client writes", async () => {
    const db = testEnv.authenticatedContext("member1").firestore();
    await assertFails(setDoc(doc(db, "spaces/space1/semanticIndex/items/items/item2"), { tokens: ["grace"] }));
    await assertFails(setDoc(doc(db, "spaces/space1/knowledgeGraph/nodes/nodes/node2"), { title: "Grace" }));
  });
});
