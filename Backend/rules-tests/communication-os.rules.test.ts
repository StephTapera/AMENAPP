/**
 * communication-os.rules.test.ts — Communication OS V1
 * Firestore Security Rules tests for thread memory, private contact notes,
 * post context, and moderation subcollections.
 *
 * Run with:
 *   cd Backend/rules-tests && npm test -- communication-os
 *
 * Requires Firebase emulators running:
 *   firebase emulators:start --only firestore
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc,
  collection,
  doc,
  getDoc,
  setDoc,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-communication-os";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore 18.rules");

const THREAD_ID = "thread123";
const MEMBER_UID = "user_member";
const NON_MEMBER_UID = "user_stranger";
const POST_ID = "post456";
const AUTHOR_UID = "post_author";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: firestoreEmulator.host,
      port: firestoreEmulator.port,
    },
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ─────────────────────────────────────────────────────────────────────────────
// Thread Memory
// ─────────────────────────────────────────────────────────────────────────────

describe("Communication OS V1 — Thread Memory", () => {
  beforeEach(async () => {
    // Seed: thread member doc and a memory doc (bypassing rules)
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `threads/${THREAD_ID}/members/${MEMBER_UID}`),
        { joinedAt: new Date() },
      );
      await setDoc(
        doc(ctx.firestore(), `threads/${THREAD_ID}/memories/mem1`),
        { title: "Test memory", type: "note", createdBy: MEMBER_UID },
      );
      await setDoc(
        doc(ctx.firestore(), `threads/${THREAD_ID}/messageContext/msg1`),
        { summary: "Context summary", createdBy: MEMBER_UID },
      );
    });
  });

  test("thread member can read thread memories", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      getDoc(doc(db, `threads/${THREAD_ID}/memories/mem1`)),
    );
  });

  test("non-member cannot read thread memories", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(doc(db, `threads/${THREAD_ID}/memories/mem1`)),
    );
  });

  test("unauthenticated user cannot read thread memories", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(doc(db, `threads/${THREAD_ID}/memories/mem1`)),
    );
  });

  test("client cannot write memory docs directly (server-only)", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(
      addDoc(collection(db, `threads/${THREAD_ID}/memories`), {
        title: "Forged memory",
        type: "note",
      }),
    );
  });

  test("thread member can read messageContext", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      getDoc(doc(db, `threads/${THREAD_ID}/messageContext/msg1`)),
    );
  });

  test("non-member cannot read messageContext", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(doc(db, `threads/${THREAD_ID}/messageContext/msg1`)),
    );
  });

  test("client cannot write messageContext docs directly (server-only)", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(
      setDoc(doc(db, `threads/${THREAD_ID}/messageContext/msg1`), {
        summary: "Forged context",
      }),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Private Contact Notes
// ─────────────────────────────────────────────────────────────────────────────

describe("Communication OS V1 — Private Contact Notes", () => {
  test("user can write their own private contact notes", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`),
        { note: "Met at conference", tags: ["friend"] },
      ),
    );
  });

  test("user can read their own private contact notes", async () => {
    // Seed via bypass
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`,
        ),
        { note: "Met at conference", tags: ["friend"] },
      );
    });

    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      getDoc(
        doc(db, `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`),
      ),
    );
  });

  test("user cannot read another user's private contact notes", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`,
        ),
        { note: "Secret note", tags: [] },
      );
    });

    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(
        doc(db, `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`),
      ),
    );
  });

  test("user cannot write to another user's private contact notes", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      setDoc(
        doc(db, `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`),
        { note: "Injected note", tags: [] },
      ),
    );
  });

  test("unauthenticated user cannot read private contact notes", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`,
        ),
        { note: "Secret note", tags: [] },
      );
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(
        doc(db, `users/${MEMBER_UID}/privateContactNotes/${NON_MEMBER_UID}`),
      ),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Saved Conversation Objects
// ─────────────────────────────────────────────────────────────────────────────

describe("Communication OS V1 — Saved Conversation Objects", () => {
  test("owner can read their saved conversation objects", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${MEMBER_UID}/savedConversationObjects/obj1`),
        { type: "link", url: "https://example.com", savedAt: new Date() },
      );
    });

    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      getDoc(doc(db, `users/${MEMBER_UID}/savedConversationObjects/obj1`)),
    );
  });

  test("other user cannot read saved conversation objects", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${MEMBER_UID}/savedConversationObjects/obj1`),
        { type: "link", url: "https://example.com", savedAt: new Date() },
      );
    });

    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(doc(db, `users/${MEMBER_UID}/savedConversationObjects/obj1`)),
    );
  });

  test("owner can write their saved conversation objects", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(
      setDoc(doc(db, `users/${MEMBER_UID}/savedConversationObjects/obj2`), {
        type: "scripture",
        reference: "John 3:16",
        savedAt: new Date(),
      }),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Post Context & Moderation
// ─────────────────────────────────────────────────────────────────────────────

describe("Communication OS V1 — Post Context", () => {
  beforeEach(async () => {
    // Seed post authored by AUTHOR_UID
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `posts/${POST_ID}`), {
        authorId: AUTHOR_UID,
        content: "Test post",
        createdAt: new Date(),
      });
      await setDoc(doc(ctx.firestore(), `posts/${POST_ID}/postContext/main`), {
        detectedLinks: [],
        detectedDates: [],
        generatedAt: new Date(),
      });
    });
  });

  test("post author can read postContext", async () => {
    const db = testEnv.authenticatedContext(AUTHOR_UID).firestore();
    await assertSucceeds(
      getDoc(doc(db, `posts/${POST_ID}/postContext/main`)),
    );
  });

  test("non-author cannot read postContext", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(doc(db, `posts/${POST_ID}/postContext/main`)),
    );
  });

  test("client cannot forge postContext docs (server-only write)", async () => {
    const db = testEnv.authenticatedContext(AUTHOR_UID).firestore();
    await assertFails(
      setDoc(doc(db, `posts/${POST_ID}/postContext/main`), {
        detectedLinks: ["https://evil.com"],
      }),
    );
  });

  test("unauthenticated user cannot read postContext", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(doc(db, `posts/${POST_ID}/postContext/main`)),
    );
  });
});

describe("Communication OS V1 — Moderation (server-only)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `posts/${POST_ID}`), {
        authorId: AUTHOR_UID,
        content: "Test post",
        createdAt: new Date(),
      });
      await setDoc(doc(ctx.firestore(), `posts/${POST_ID}/moderation/main`), {
        severity: "safe",
        allowed: true,
        checkedAt: new Date(),
      });
    });
  });

  test("author cannot read moderation docs (server-only)", async () => {
    const db = testEnv.authenticatedContext(AUTHOR_UID).firestore();
    await assertFails(
      getDoc(doc(db, `posts/${POST_ID}/moderation/main`)),
    );
  });

  test("non-author cannot read moderation docs", async () => {
    const db = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertFails(
      getDoc(doc(db, `posts/${POST_ID}/moderation/main`)),
    );
  });

  test("client cannot forge moderation docs", async () => {
    const db = testEnv.authenticatedContext(AUTHOR_UID).firestore();
    await assertFails(
      setDoc(doc(db, `posts/${POST_ID}/moderation/main`), {
        severity: "safe",
        allowed: true,
      }),
    );
  });

  test("unauthenticated user cannot read moderation docs", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(doc(db, `posts/${POST_ID}/moderation/main`)),
    );
  });
});
