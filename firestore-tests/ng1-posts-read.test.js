/**
 * NG-1 two-sided rules test — posts read gate (visible == true + owner bypass).
 *
 * Run:
 *   cd firestore-tests && npm install
 *   firebase emulators:exec --only firestore "node ng1-posts-read.test.js"
 *
 * Exit 0 = all assertions passed. Non-zero = a deny/allow expectation failed.
 */
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "amen-ng1-rules-test";

async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  // Seed posts with rules disabled.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("posts/pending").set({
      authorId: "alice",
      privacyLevel: "public",
      visibility: "everyone",
      content: "unmoderated",
      visible: false, // not yet cleared by moderatePost
    });
    await db.doc("posts/approved").set({
      authorId: "alice",
      privacyLevel: "public",
      visibility: "everyone",
      content: "approved",
      visible: true, // moderatePost cleared it
    });
  });

  const alice = env.authenticatedContext("alice").firestore();
  const bob = env.authenticatedContext("bob").firestore();

  let failures = 0;
  const check = async (label, p) => {
    try { await p; console.log(`  PASS  ${label}`); }
    catch (e) { failures++; console.error(`  FAIL  ${label} — ${e.message}`); }
  };

  // Owner bypass: alice reads her own pending (visible:false) post.
  await check("owner reads own pending post (allow)",
    assertSucceeds(alice.doc("posts/pending").get()));

  // NG-1 core: non-owner CANNOT read a public post before moderation clears it.
  await check("non-owner blocked from pending public post (deny)",
    assertFails(bob.doc("posts/pending").get()));

  // Non-owner CAN read a public post once visible:true.
  await check("non-owner reads approved public post (allow)",
    assertSucceeds(bob.doc("posts/approved").get()));

  await env.cleanup();
  if (failures > 0) { console.error(`\nNG-1: ${failures} assertion(s) failed`); process.exit(1); }
  console.log("\nNG-1: all assertions passed");
}

main().catch((e) => { console.error(e); process.exit(1); });
