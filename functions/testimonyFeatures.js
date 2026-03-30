const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten, onDocumentUpdated } = require("firebase-functions/v2/firestore");

const db = admin.firestore();

/**
 * cleanStaleWitnesses — runs every 60 seconds, deletes witness presence docs
 * older than 60 seconds from all active subcollections.
 */
exports.cleanStaleWitnesses = onSchedule(
  { schedule: "every 1 minutes", timeoutSeconds: 30 },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const witnessesRef = db.collection("witnesses");
    const postSnap = await witnessesRef.listDocuments();

    const batchOps = [];
    for (const postDoc of postSnap) {
      const activeSnap = await postDoc.collection("active")
        .where("timestamp", "<", cutoff)
        .get();
      for (const doc of activeSnap.docs) {
        batchOps.push(doc.ref.delete());
      }
    }
    await Promise.all(batchOps);
    console.log(`cleanStaleWitnesses: deleted ${batchOps.length} stale docs`);
  }
);

/**
 * updateTestimonyStrength — triggers on writes to posts/{postId}.
 * Recomputes testimonyStrength from sub-signals and writes it back.
 */
exports.updateTestimonyStrength = onDocumentWritten(
  "posts/{postId}",
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return;
    if (data.category !== "testimonies") return;

    const postId = event.params.postId;

    // Gather signals
    const witnessCount    = data.witnessCount    || 0;
    const prayerEchoCount = data.prayerEchoCount || 0;
    const scriptureCount  = data.scriptureCount  || 0;
    const amenCount       = data.amenCount        || 0;
    const neededCount     = data.neededCount      || 0;

    // Score calculation
    let score = 0;
    score += witnessCount    * 10;   // each witness tap
    score += prayerEchoCount * 12;   // prayer echoes
    score += scriptureCount  * 15;   // scripture references in replies
    score += amenCount       * 5;    // claps/amens
    score += neededCount     * 5;    // needed this
    score = Math.min(100, score);

    // Don't write if unchanged (avoid trigger loop)
    if ((data.testimonyStrength || 0) === score) return;

    const update = { testimonyStrength: score };

    // Milestone: hit 100 → write to milestones collection
    if (score >= 100 && (data.testimonyStrength || 0) < 100) {
      await db.collection("milestones").add({
        postId,
        authorId: data.authorId,
        type: "testimonyStrengthMax",
        achievedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return db.collection("posts").doc(postId).update(update);
  }
);

/**
 * onNeededThisWrite — triggers when neededCount increments on a post.
 * At 10+: sends FCM push to testimony author.
 */
exports.onNeededThisWrite = onDocumentUpdated(
  "posts/{postId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!before || !after) return;
    if (after.category !== "testimonies") return;

    const neededBefore = before.neededCount || 0;
    const neededAfter  = after.neededCount  || 0;

    // Only act when incrementing past threshold
    if (neededAfter < 10 || neededBefore >= 10) return;

    const authorId = after.authorId;
    if (!authorId) return;

    // Fetch author tokens
    const userDoc = await db.collection("users").doc(authorId).get();
    const tokens = userDoc.data()?.fcmTokens || [];
    if (!tokens.length) return;

    const postId = event.params.postId;

    // Send push
    const message = {
      notification: {
        title: "Your testimony is reaching people",
        body: "10 people saved your testimony — keep sharing.",
      },
      data: { type: "neededThis", postId },
    };
    await admin.messaging().sendEachForMulticast({ tokens, ...message });

    // Write to weekly digest
    await db.collection("weeklyDigest").doc(authorId)
      .collection("items").add({
        type: "neededThis",
        postId,
        count: neededAfter,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  }
);
