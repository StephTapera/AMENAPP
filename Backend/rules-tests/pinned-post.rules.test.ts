/**
 * Firestore Security Rules — Pinned Post tests
 *
 * Prerequisites:
 *   1. cd Backend/rules-tests && npm install
 *   2. firebase emulators:start --only firestore   (separate terminal)
 *   3. npm test
 *
 * Rules file under test: AMENAPP/firestore.deploy.rules
 * Tests cover Branch 5 (users/{userId} update) + validatePinnedPostWrite().
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, updateDoc, deleteField, Timestamp } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

let testEnv: RulesTestEnvironment;

// ─────────────────────────────────────────────
// Shared fixture data
// ─────────────────────────────────────────────

const OWNER_UID = "user-owner-001";
const OTHER_UID = "user-other-002";
const POST_ID   = "post-abc-123";

const validPinFields = () => ({
  pinnedPostId: POST_ID,
  pinnedAt: Timestamp.now(),
  profilePinnedPost: {
    postId: POST_ID,
    isPinned: true,
    semanticTags: ["Prayer"],
  },
});

const unpinFields = () => ({
  pinnedPostId: deleteField(),
  pinnedAt: deleteField(),
  pinnedUntil: deleteField(),
  profilePinnedPost: deleteField(),
});

// ─────────────────────────────────────────────
// Setup / teardown
// ─────────────────────────────────────────────

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

  // Seed: owner user doc
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER_UID), {
      username: "owner",
      email: "owner@example.com",
    });

    // Seed: post owned by OWNER_UID
    await setDoc(doc(db, "posts", POST_ID), {
      authorId: OWNER_UID,
      content: "My pinnable post",
      isRemoved: false,
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────

describe("Pinned post — Branch 5 update rule", () => {

  test("T1: owner can pin their own post", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users", OWNER_UID), validPinFields())
    );
  });

  test("T2: owner can unpin (delete all pin fields)", async () => {
    // First pin via admin bypass
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await updateDoc(doc(db, "users", OWNER_UID), validPinFields());
    });

    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users", OWNER_UID), unpinFields())
    );
  });

  test("T3: owner can atomically replace pin (single updateDoc)", async () => {
    const NEW_POST_ID = "post-new-456";

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      // Seed a second post owned by OWNER_UID
      await setDoc(doc(db, "posts", NEW_POST_ID), {
        authorId: OWNER_UID,
        content: "Replacement post",
        isRemoved: false,
      });
      // Seed initial pin
      await updateDoc(doc(db, "users", OWNER_UID), validPinFields());
    });

    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: NEW_POST_ID,
        pinnedAt: Timestamp.now(),
        profilePinnedPost: {
          postId: NEW_POST_ID,
          isPinned: true,
          semanticTags: [],
        },
      })
    );
  });

  test("T4: non-owner cannot pin another user's profile", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), validPinFields())
    );
  });

  test("T5: owner cannot pin a post they don't own (authorId mismatch)", async () => {
    const OTHER_POST_ID = "post-other-999";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "posts", OTHER_POST_ID), {
        authorId: OTHER_UID,   // owned by a different user
        content: "Someone else's post",
        isRemoved: false,
      });
    });

    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: OTHER_POST_ID,
        pinnedAt: Timestamp.now(),
        profilePinnedPost: {
          postId: OTHER_POST_ID,
          isPinned: true,
          semanticTags: [],
        },
      })
    );
  });

  test("T6: owner cannot pin a deleted/removed post (isRemoved: true)", async () => {
    const REMOVED_POST_ID = "post-removed-777";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "posts", REMOVED_POST_ID), {
        authorId: OWNER_UID,
        content: "Was removed",
        isRemoved: true,
      });
    });

    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: REMOVED_POST_ID,
        pinnedAt: Timestamp.now(),
        profilePinnedPost: {
          postId: REMOVED_POST_ID,
          isPinned: true,
          semanticTags: [],
        },
      })
    );
  });

  test("T7: owner cannot pin a non-existent post", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: "post-does-not-exist",
        pinnedAt: Timestamp.now(),
        profilePinnedPost: {
          postId: "post-does-not-exist",
          isPinned: true,
          semanticTags: [],
        },
      })
    );
  });

  test("T8: write rejected when profilePinnedPost is not a map", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: POST_ID,
        pinnedAt: Timestamp.now(),
        profilePinnedPost: "invalid-string-not-a-map",  // wrong type
      })
    );
  });

  test("T9: write rejected when profilePinnedPost.postId does not match pinnedPostId", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        pinnedPostId: POST_ID,
        pinnedAt: Timestamp.now(),
        profilePinnedPost: {
          postId: "DIFFERENT-POST-ID",  // cross-field mismatch
          isPinned: true,
          semanticTags: [],
        },
      })
    );
  });

  test("T10: write rejected when extra non-pin fields are included", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      updateDoc(doc(db, "users", OWNER_UID), {
        ...validPinFields(),
        username: "hacked-username",  // not in pin allowlist
      })
    );
  });

});
