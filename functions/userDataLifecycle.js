/**
 * userDataLifecycle.js — GDPR / CCPA Privacy Lifecycle Callables
 *
 * Provides three user-facing callables for privacy rights:
 *
 *   exportUserData         — "Download My Data" (rate-limited, recent-auth required)
 *   deleteBereanHistory    — Erase all Berean AI conversation history + Pinecone vectors
 *   deleteAccountData      — Full hard-delete (nuclear option, 5-min auth window)
 *
 * Security gates on every callable:
 *   - request.auth required (unauthenticated → UNAUTHENTICATED error)
 *   - Recent-auth check via request.auth.token.auth_time
 *     export / deleteBerean → 10-min window
 *     deleteAccount         →  5-min window (tighter for destructive ops)
 *
 * Pinecone strategy:
 *   The existing mlClients.pineconeDelete(namespace, ids[]) deletes by vector ID.
 *   Pinecone also supports deleteAll-by-metadata via a filter object, but only on
 *   pods-based indexes that have been configured to allow metadata filtering on the
 *   delete endpoint.  We attempt delete-by-metadata first; if the API returns an
 *   error we fall back to creating a `pineconeCleanupJobs/{uid}` Firestore document
 *   so an admin job can drain it.  Either way the callable succeeds.
 */

"use strict";

const admin   = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const { logFunction }        = require("./mlClients");

const PINECONE_API_KEY = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST    = defineSecret("PINECONE_HOST");

const db      = admin.firestore();
const REGION  = "us-central1";

// ─── Auth-time guard ──────────────────────────────────────────────────────────

/**
 * Throws failed-precondition if the user's Firebase ID token was issued more
 * than `maxAgeSeconds` ago.  Cloud Functions receive `auth_time` in seconds.
 */
function assertRecentAuth(request, maxAgeSeconds) {
  const authTime = request.auth?.token?.auth_time; // seconds since epoch
  if (!authTime) {
    throw new HttpsError(
      "failed-precondition",
      "Please re-authenticate before continuing."
    );
  }
  const ageSeconds = Math.floor(Date.now() / 1000) - authTime;
  if (ageSeconds > maxAgeSeconds) {
    throw new HttpsError(
      "failed-precondition",
      "Please re-authenticate before continuing. Your session is too old for this operation."
    );
  }
}

// ─── Pinecone delete-by-metadata helper ───────────────────────────────────────

/**
 * Attempt to delete all Pinecone vectors for `uid` across the berean-related
 * namespaces using the delete-by-metadata filter API.
 *
 * Falls back gracefully:
 *   - If Pinecone secrets are absent → log and queue a cleanup job.
 *   - If the API call fails (e.g. index doesn't support filter delete) → same.
 *
 * @param {string} uid
 * @param {string} callerFunction  — name used in log lines
 * @returns {Promise<{queued: boolean, attempted: boolean}>}
 */
async function deletePineconeVectorsForUser(uid, callerFunction) {
  const apiKey = process.env.PINECONE_API_KEY;
  const host   = process.env.PINECONE_HOST;

  if (!apiKey || !host) {
    console.warn(`[${callerFunction}] Pinecone secrets not available — queueing cleanup job for uid=${uid}`);
    await queuePineconeCleanup(uid, callerFunction, "secrets_unavailable");
    return { queued: true, attempted: false };
  }

  // Namespaces that may contain user-generated vectors
  const namespacesToClear = [
    "prayer-partner-pool",        // vector id: `user_${uid}`
    "user-interest-embeddings",   // vector id: uid
    "testimony-embeddings",       // metadata.authorId == uid (delete by filter)
  ];

  let anyFailed = false;

  for (const namespace of namespacesToClear) {
    try {
      if (namespace === "prayer-partner-pool" || namespace === "user-interest-embeddings") {
        // These use uid as the vector ID — delete by explicit ID (always supported)
        await fetch(`https://${host}/vectors/delete`, {
          method: "POST",
          headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
          body: JSON.stringify({ ids: [uid, `user_${uid}`], namespace }),
          signal: AbortSignal.timeout(5000),
        });
      } else {
        // testimony-embeddings — delete by authorId metadata filter
        // This requires the index to support metadata-filtered deletes (pods-based)
        const resp = await fetch(`https://${host}/vectors/delete`, {
          method: "POST",
          headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
          body: JSON.stringify({
            filter: { authorId: { $eq: uid } },
            namespace,
          }),
          signal: AbortSignal.timeout(10000),
        });

        if (!resp.ok) {
          const text = await resp.text().catch(() => "");
          console.warn(`[${callerFunction}] Pinecone filter-delete rejected for namespace=${namespace}: ${text} — queueing`);
          anyFailed = true;
        }
      }
    } catch (err) {
      console.warn(`[${callerFunction}] Pinecone delete error for namespace=${namespace}: ${err.message} — queueing`);
      anyFailed = true;
    }
  }

  if (anyFailed) {
    await queuePineconeCleanup(uid, callerFunction, "partial_api_failure");
    return { queued: true, attempted: true };
  }

  console.log(`[${callerFunction}] Pinecone vectors cleared for uid=${uid}`);
  return { queued: false, attempted: true };
}

async function queuePineconeCleanup(uid, requestedBy, reason) {
  await db.collection("pineconeCleanupJobs").doc(uid).set({
    uid,
    requestedBy,
    reason,
    namespaces: ["prayer-partner-pool", "user-interest-embeddings", "testimony-embeddings"],
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

// ─── Recursive subcollection delete helper ───────────────────────────────────

async function deleteSubcollectionDocs(collRef) {
  const snap = await collRef.limit(200).get();
  if (snap.empty) return 0;

  let count = snap.size;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();

  if (snap.size === 200) {
    count += await deleteSubcollectionDocs(collRef);
  }
  return count;
}

// ─── Batch-delete an array of DocumentSnapshots ───────────────────────────────

async function batchDeleteDocs(docs) {
  const BATCH_SIZE = 400;
  let deleted = 0;
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_SIZE).forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += docs.slice(i, i + BATCH_SIZE).length;
  }
  return deleted;
}

// =============================================================================
// 1. EXPORT USER DATA
// =============================================================================

exports.exportUserData = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    assertRecentAuth(request, 10 * 60); // 10-minute window

    const uid = request.auth.uid;
    const now = Date.now();

    // ── Rate limit: max 3 exports per 24 hours ───────────────────────────────
    const oneDayAgo = admin.firestore.Timestamp.fromMillis(now - 24 * 60 * 60 * 1000);
    const recentExports = await db.collection(`users/${uid}/dataExports`)
      .where("createdAt", ">", oneDayAgo)
      .get();

    if (recentExports.size >= 3) {
      throw new HttpsError(
        "resource-exhausted",
        "You may request at most 3 data exports per 24 hours. Please try again later."
      );
    }

    // Log export initiated — no content in log
    console.log(JSON.stringify({
      severity: "INFO",
      function: "exportUserData",
      event: "export_initiated",
      uid, // uid only, no content
      timestamp: new Date().toISOString(),
    }));

    try {
      const exportId = db.collection("_").doc().id; // generate a random ID
      const exportData = {
        exportedAt: new Date().toISOString(),
        userId: uid,
        sections: {},
      };

      // 1. User profile (strip internal/device fields)
      const userDoc = await db.collection("users").doc(uid).get();
      if (userDoc.exists) {
        const ud = { ...userDoc.data() };
        ["fcmToken", "deviceTokens", "fcmTokens", "apnsToken", "pushToken"].forEach((f) => delete ud[f]);
        exportData.sections.profile = ud;
      }

      // 2. Prayers (last 500)
      const prayersSnap = await db.collection(`users/${uid}/prayers`)
        .orderBy("createdAt", "desc")
        .limit(500)
        .get();
      exportData.sections.prayers = prayersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      // 3. Prayer reflections (last 500)
      const reflectionsSnap = await db.collection(`users/${uid}/prayerReflections`)
        .orderBy("createdAt", "desc")
        .limit(500)
        .get();
      exportData.sections.prayerReflections = reflectionsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      // 4. Berean conversation summaries — metadata only, no message content
      const bereanSnap = await db.collection(`users/${uid}/bereanConversations`)
        .orderBy("createdAt", "desc")
        .limit(200)
        .get();
      exportData.sections.bereanConversationSummaries = bereanSnap.docs.map((d) => {
        const data = d.data();
        return {
          convId:       d.id,
          createdAt:    data.createdAt || null,
          updatedAt:    data.updatedAt || null,
          messageCount: data.messageCount || 0,
          title:        data.title        || null,
        };
      });

      // 5. Church notes — metadata only (noteId, title, createdAt)
      const notesSnap = await db.collection(`users/${uid}/churchNotes`)
        .orderBy("createdAt", "desc")
        .limit(200)
        .get();
      exportData.sections.churchNotesSummaries = notesSnap.docs.map((d) => {
        const data = d.data();
        return {
          noteId:    d.id,
          title:     data.title     || null,
          createdAt: data.createdAt || null,
        };
      });

      // 6. Posts authored by user (last 100)
      const postsSnap = await db.collection("posts")
        .where("authorId", "==", uid)
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();
      exportData.sections.posts = postsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      // 7. Testimonies authored by user (last 100)
      const testimoniesSnap = await db.collection("posts")
        .where("authorId", "==", uid)
        .where("category", "in", ["testimony", "testimonies"])
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();
      exportData.sections.testimonies = testimoniesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      // ── Persist export for download ──────────────────────────────────────
      await db.collection(`users/${uid}/dataExports`).doc(exportId).set({
        exportId,
        status:    "complete",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sectionCount: Object.keys(exportData.sections).length,
        data:      exportData,
      });

      logFunction("exportUserData", {
        uid,
        exportId,
        sectionCount: Object.keys(exportData.sections).length,
      });

      return exportData;
    } catch (err) {
      console.error(`[exportUserData] Failed for uid=${uid}:`, err);
      throw new HttpsError("internal", "Data export failed. Please try again.");
    }
  }
);

// =============================================================================
// 2. DELETE BEREAN HISTORY
// =============================================================================

exports.deleteBereanHistory = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    secrets: [PINECONE_API_KEY, PINECONE_HOST],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    assertRecentAuth(request, 10 * 60); // 10-minute window

    const uid = request.auth.uid;
    let firestoreDocsDeleted = 0;

    try {
      // 1. Delete users/{uid}/bereanConversations/* and their messages subcollections
      const userConvRef = db.collection(`users/${uid}/bereanConversations`);
      const userConvSnap = await userConvRef.get();

      for (const convDoc of userConvSnap.docs) {
        // Delete messages subcollection
        firestoreDocsDeleted += await deleteSubcollectionDocs(
          convDoc.ref.collection("messages")
        );
        // Delete the conversation doc itself
        await convDoc.ref.delete();
        firestoreDocsDeleted++;
      }

      // 2. Delete bereanConversations/{uid}/* (alternate top-level path)
      const topConvRef = db.collection("bereanConversations").doc(uid);
      const topConvDocSnap = await topConvRef.get();
      if (topConvDocSnap.exists) {
        // Delete any subcollections under this document
        const subCollections = ["messages", "sessions", "contexts"];
        for (const sub of subCollections) {
          firestoreDocsDeleted += await deleteSubcollectionDocs(topConvRef.collection(sub));
        }
        await topConvRef.delete();
        firestoreDocsDeleted++;
      }

      // Also delete docs where bereanConversations/{uid}/{convId}
      const topLevelConvsSnap = await db.collection("bereanConversations")
        .doc(uid)
        .listCollections()
        .catch(() => []);

      // Handle case where bereanConversations/{uid} is used as a collection path
      // (some implementations store conversations as bereanConversations/{uid}/{convId})
      const altConvSnap = await db.collection("bereanConversations")
        .where("userId", "==", uid)
        .limit(200)
        .get()
        .catch(() => ({ docs: [] }));

      if (!altConvSnap.docs?.length === false && altConvSnap.docs?.length > 0) {
        firestoreDocsDeleted += await batchDeleteDocs(altConvSnap.docs);
      }

      // 3. Delete users/{uid}/bereanMemory/*
      firestoreDocsDeleted += await deleteSubcollectionDocs(
        db.collection(`users/${uid}/bereanMemory`)
      );

      // 4. Delete bereanMemory docs where userId == uid (top-level collection)
      const bereanMemorySnap = await db.collection("bereanMemory")
        .where("userId", "==", uid)
        .limit(200)
        .get()
        .catch(() => ({ docs: [] }));
      if (bereanMemorySnap.docs?.length > 0) {
        firestoreDocsDeleted += await batchDeleteDocs(bereanMemorySnap.docs);
      }

      // 5. Pinecone vector deletion for this user
      const pineconeResult = await deletePineconeVectorsForUser(uid, "deleteBereanHistory");

      // 6. Write tombstone so the app can display "history cleared on X date"
      await db.doc(`users/${uid}/bereanHistoryDeleted`).set({
        clearedAt:  admin.firestore.FieldValue.serverTimestamp(),
        clearedByUser: true,
      });

      logFunction("deleteBereanHistory", {
        uid,
        firestoreDocsDeleted,
        pineconeQueued: pineconeResult.queued,
        pineconeAttempted: pineconeResult.attempted,
      });

      return {
        deleted: true,
        firestoreDocsDeleted,
        pineconeVectorsQueued: pineconeResult.queued,
      };
    } catch (err) {
      console.error(`[deleteBereanHistory] Failed for uid=${uid}:`, err);
      throw new HttpsError("internal", "Failed to delete Berean history. Please try again.");
    }
  }
);

// =============================================================================
// 3. DELETE ACCOUNT DATA  (nuclear option)
// =============================================================================

exports.deleteAccountData = onCall(
  {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 540,
    secrets: [PINECONE_API_KEY, PINECONE_HOST],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    // Tighter 5-minute window for the destructive nuclear delete
    assertRecentAuth(request, 5 * 60);

    const uid = request.auth.uid;

    // ── Idempotency guard ────────────────────────────────────────────────────
    // If a completed job already exists, return success without re-running.
    const jobRef = db.collection("userDeletionJobs").doc(uid);
    const existingJob = await jobRef.get();
    if (existingJob.exists && existingJob.data()?.status === "complete") {
      console.log(`[deleteAccountData] Already completed for uid=${uid} — idempotent no-op`);
      return {
        deleted: true,
        message: "Account deletion initiated. Your data will be fully removed.",
      };
    }

    // ── Step 1: Queue deletion job ────────────────────────────────────────────
    await jobRef.set({
      uid,
      status:    "queued",
      queuedAt:  admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const errors = [];

    // ── Step 2a: Collect data needed before deletion ──────────────────────────
    let username = null;
    let postIds  = [];

    try {
      const [userSnap, postsSnap] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("posts").where("authorId", "==", uid).select().get(),
      ]);
      username = userSnap.data()?.username || userSnap.data()?.userName || null;
      postIds  = postsSnap.docs.map((d) => d.id);
      console.log(`[deleteAccountData] Pre-delete: ${postIds.length} posts, username=${username}`);
    } catch (e) {
      console.warn(`[deleteAccountData] Pre-delete data collection error for uid=${uid}: ${e.message}`);
    }

    // ── Step 2b: Delete Storage files ────────────────────────────────────────
    try {
      const bucket = admin.storage().bucket();
      const storagePathPrefixes = [
        `users/${uid}/`,
        `churchNotes/${uid}/`,
        `profile_images/${uid}/`,
        `post_media/${uid}/`,
        `testimony_media/${uid}/`,
        `message_attachments/${uid}/`,
        `verification_docs/${uid}/`,
      ];
      for (const prefix of storagePathPrefixes) {
        await bucket.deleteFiles({ prefix }).catch((e) => {
          console.warn(`[deleteAccountData] Storage prefix delete failed ${prefix}: ${e.message}`);
        });
      }
      console.log(`[deleteAccountData] Storage cleared for uid=${uid}`);
    } catch (e) {
      errors.push(`storage: ${e.message}`);
      console.error(`[deleteAccountData] Storage error: ${e.message}`);
    }

    // ── Step 2c: Pinecone vector deletion ─────────────────────────────────────
    try {
      const pineconeResult = await deletePineconeVectorsForUser(uid, "deleteAccountData");
      // Also delete testimony vectors by postId if we have them
      if (postIds.length > 0) {
        const apiKey = process.env.PINECONE_API_KEY;
        const host   = process.env.PINECONE_HOST;
        if (apiKey && host) {
          const BATCH = 1000;
          for (let i = 0; i < postIds.length; i += BATCH) {
            const batch = postIds.slice(i, i + BATCH);
            await fetch(`https://${host}/vectors/delete`, {
              method: "POST",
              headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
              body: JSON.stringify({ ids: batch, namespace: "testimony-embeddings" }),
              signal: AbortSignal.timeout(10000),
            }).catch((e) => console.warn(`[deleteAccountData] Pinecone testimony batch delete failed: ${e.message}`));
            await fetch(`https://${host}/vectors/delete`, {
              method: "POST",
              headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
              body: JSON.stringify({ ids: batch, namespace: "content-embeddings" }),
              signal: AbortSignal.timeout(10000),
            }).catch((e) => console.warn(`[deleteAccountData] Pinecone content batch delete failed: ${e.message}`));
          }
        }
      }
      console.log(`[deleteAccountData] Pinecone cleared for uid=${uid}, queued=${pineconeResult.queued}`);
    } catch (e) {
      errors.push(`pinecone: ${e.message}`);
      console.error(`[deleteAccountData] Pinecone error: ${e.message}`);
    }

    // ── Step 2d: Firestore — user subcollections ──────────────────────────────
    try {
      const userRef = db.collection("users").doc(uid);
      const spiritualSubcollections = [
        "bereanConversations",
        "bereanMemory",
        "prayers",
        "prayerReflections",
        "blessedLater",
        "unsentThoughts",
        "living_entries",
        "churchNotes",
        "dataExports",
        "bereanHistoryDeleted",
        "followers",
        "following",
        "followRequests",
        "blockedUsers",
        "savedPosts",
        "savedNotes",
        "notifications",
        "notificationPreferences",
        "privacySettings",
        "languagePreferences",
        "wellness",
        "berean_feedback",
        "bereanUsage",
        "bookmarkedMedia",
        "mediaHistory",
        "readingProgress",
        "completedReflections",
        "fcmTokens",
        "prayerRequests",
        "compose_suggestion_feedback",
        "selah_journal",
        "journal",
      ];
      for (const sub of spiritualSubcollections) {
        await deleteSubcollectionDocs(userRef.collection(sub)).catch((e) =>
          console.warn(`[deleteAccountData] Subcollection ${sub} delete partial: ${e.message}`)
        );
      }
      // Delete the user document itself
      await userRef.delete();
      console.log(`[deleteAccountData] Firestore user doc + subcollections cleared for uid=${uid}`);
    } catch (e) {
      errors.push(`firestore_user: ${e.message}`);
      console.error(`[deleteAccountData] Firestore user error: ${e.message}`);
    }

    // ── Step 2e: Firestore — username lookup ──────────────────────────────────
    if (username) {
      await db.collection("usernameLookup").doc(username).delete().catch((e) =>
        console.warn(`[deleteAccountData] usernameLookup delete failed: ${e.message}`)
      );
    }

    // ── Step 2f: Firestore — top-level collections owned by user ─────────────
    const ownedCollections = [
      { col: "posts",               field: "authorId"    },
      { col: "notifications",       field: "recipientId" },
      { col: "notificationTokens",  field: "userId"      },
      { col: "draftPosts",          field: "authorId"    },
      { col: "dataExportRequests",  field: "userId"      },
      { col: "dataExportLog",       field: "userId"      },
      { col: "algoliaSync",         field: "userId"      },
      { col: "deletionRequests",    field: "userId"      },
    ];

    for (const { col, field } of ownedCollections) {
      try {
        let snap = await db.collection(col).where(field, "==", uid).limit(200).get();
        while (!snap.empty) {
          await batchDeleteDocs(snap.docs);
          snap = await db.collection(col).where(field, "==", uid).limit(200).get();
        }
      } catch (e) {
        console.warn(`[deleteAccountData] Collection ${col} delete failed: ${e.message}`);
      }
    }

    // Also remove follow relationships referencing this user
    for (const field of ["followerId", "followingId"]) {
      try {
        let snap = await db.collection("follows").where(field, "==", uid).limit(200).get();
        while (!snap.empty) {
          await batchDeleteDocs(snap.docs);
          snap = await db.collection("follows").where(field, "==", uid).limit(200).get();
        }
      } catch (e) {
        console.warn(`[deleteAccountData] follows.${field} delete failed: ${e.message}`);
      }
    }

    // ── Step 2g: DM redaction (preserve other participant's history) ──────────
    // We do NOT delete the whole conversation. Instead we redact the user's
    // messages so the other participant retains their copy.
    try {
      const convoSnap = await db.collection("conversations")
        .where("participants", "array-contains", uid)
        .limit(200)
        .get();

      for (const convoDoc of convoSnap.docs) {
        // Mark user as a deleted participant on the conversation
        await convoDoc.ref.update({
          deletedParticipants: admin.firestore.FieldValue.arrayUnion(uid),
        }).catch(() => {});

        // Redact messages authored by this user
        const msgSnap = await convoDoc.ref.collection("messages")
          .where("authorId", "==", uid)
          .limit(500)
          .get();

        if (!msgSnap.empty) {
          const BATCH_SIZE = 400;
          for (let i = 0; i < msgSnap.docs.length; i += BATCH_SIZE) {
            const batch = db.batch();
            msgSnap.docs.slice(i, i + BATCH_SIZE).forEach((msgDoc) => {
              batch.update(msgDoc.ref, {
                content:  "[deleted]",
                authorId: "[deleted]",
                redacted: true,
              });
            });
            await batch.commit();
          }
        }
      }
      console.log(`[deleteAccountData] DM messages redacted for uid=${uid}`);
    } catch (e) {
      errors.push(`dm_redaction: ${e.message}`);
      console.error(`[deleteAccountData] DM redaction error: ${e.message}`);
    }

    // ── Step 2h: Berean top-level path cleanup ────────────────────────────────
    try {
      // bereanConversations/{uid}/* (alternate top-level path)
      const bereanTopRef = db.collection("bereanConversations").doc(uid);
      const topSnap = await bereanTopRef.get();
      if (topSnap.exists) {
        for (const sub of ["messages", "sessions", "contexts"]) {
          await deleteSubcollectionDocs(bereanTopRef.collection(sub)).catch(() => {});
        }
        await bereanTopRef.delete();
      }
    } catch (e) {
      console.warn(`[deleteAccountData] Berean top-level cleanup failed: ${e.message}`);
    }

    // ── Step 2i: Comments authored by user (collection group) ─────────────────
    try {
      const commentsSnap = await db.collectionGroup("comments")
        .where("authorId", "==", uid)
        .get();
      if (!commentsSnap.empty) {
        await batchDeleteDocs(commentsSnap.docs);
      }
    } catch (e) {
      console.warn(`[deleteAccountData] Comments group delete failed: ${e.message}`);
    }

    // ── Step 3: Firebase Auth deletion — MUST BE LAST ─────────────────────────
    // Deleting the auth account terminates the user's identity; any subsequent
    // admin.auth() operations that reference the uid continue to work since we
    // use the uid string, not the live auth session.
    try {
      await admin.auth().deleteUser(uid);
      console.log(`[deleteAccountData] Auth user deleted for uid=${uid}`);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        console.log(`[deleteAccountData] Auth user already deleted for uid=${uid} — idempotent`);
      } else {
        errors.push(`auth: ${e.message}`);
        console.error(`[deleteAccountData] Auth deletion error: ${e.message}`);
      }
    }

    // ── Step 4: Update job status ──────────────────────────────────────────────
    const finalStatus = errors.length === 0 ? "complete" : "complete_with_errors";
    await jobRef.set({
      status:      finalStatus,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(errors.length > 0 ? { errors } : {}),
    }, { merge: true });

    logFunction("deleteAccountData", {
      uid,
      status: finalStatus,
      errorCount: errors.length,
    });

    return {
      deleted: true,
      message: "Account deletion initiated. Your data will be fully removed.",
    };
  }
);
