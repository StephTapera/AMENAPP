/**
 * Cloud Functions for Authentication
 * P0-2: Username Uniqueness Transaction
 * P0-3: Account Deletion Cascade
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentDeleted} = require("firebase-functions/v2/firestore");

// ============================================================================
// H-03: BAN EVASION PREVENTION — Phone number ban check
// Hashes phone numbers with SHA-256 before storing so the raw number is never
// persisted in Firestore. Checked on account creation and user doc creation.
// ============================================================================

const crypto = require("crypto");

/**
 * Hash a phone number with SHA-256 for safe storage in bannedPhones/{hash}.
 * @param {string} phoneNumber - E.164 format phone number
 * @returns {string} hex digest
 */
function hashPhoneNumber(phoneNumber) {
  return crypto.createHash("sha256").update(phoneNumber.trim()).digest("hex");
}

/**
 * Throws an HttpsError if the given phone number has been banned.
 * No-ops silently when phoneNumber is absent (email-only accounts).
 * @param {string|null|undefined} phoneNumber
 */
async function checkPhoneNotBanned(phoneNumber) {
  if (!phoneNumber) return;
  const hash = hashPhoneNumber(phoneNumber);
  const banned = await admin.firestore().collection("bannedPhones").doc(hash).get();
  if (banned.exists) {
    throw new HttpsError(
        "permission-denied",
        "This phone number is not eligible for registration."
    );
  }
}

// ============================================================================
// H-04: ACCOUNT CREATION RATE LIMIT
// Imported here for use in reserveUsername.
// ============================================================================
const {enforceRateLimit} = require("./rateLimiter");

/**
 * P0-2: Reserve a username using a transaction
 * This prevents race conditions when two users try to claim the same username
 *
 * Call this BEFORE creating the user document
 *
 * @param {string} username - The desired username (will be lowercased)
 * @param {string} userId - The user ID claiming this username
 * @returns {object} - {success: true} or throws error
 */
exports.reserveUsername = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR // Set to true in production with App Check
    },
    async (request) => {
      const {username, userId} = request.data;
      const requesterId = request.auth?.uid;

      console.log(`🔐 Username reservation request: "${username}" for user ${userId}`);

      // Validate authentication
      if (!requesterId) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to reserve a username"
        );
      }

      // Validate that requester is reserving for themselves
      if (requesterId !== userId) {
        throw new HttpsError(
            "permission-denied",
            "You can only reserve usernames for yourself"
        );
      }

      // H-04: Rate limit username reservation attempts per UID to prevent
      // abuse of the account creation flow. Firebase Auth handles IP-level
      // rate limiting for phone number verification separately.
      // Note: rate limiting by IP is handled by Firebase Auth for phone numbers.
      // Here we limit username reservation attempts by UID to prevent abuse of the creation flow.
      await enforceRateLimit(requesterId, "account_create", 2, 86400); // 2 attempts per day per UID

      // Validate input
      if (!username || typeof username !== "string") {
        throw new HttpsError(
            "invalid-argument",
            "Username is required and must be a string"
        );
      }

      // Normalize username (lowercase, trim)
      const normalizedUsername = username.trim().toLowerCase();

      // Validate username format
      if (!/^[a-z0-9_]{3,20}$/.test(normalizedUsername)) {
        throw new HttpsError(
            "invalid-argument",
            "Username must be 3-20 characters and contain only lowercase letters, numbers, and underscores"
        );
      }

      try {
        const db = admin.firestore();
        const usernamesRef = db.collection("usernames");
        const usernameDocRef = usernamesRef.doc(normalizedUsername);

        // Run transaction to claim username atomically
        await db.runTransaction(async (transaction) => {
          const usernameDoc = await transaction.get(usernameDocRef);

          if (usernameDoc.exists) {
            const existingUserId = usernameDoc.data().userId;

            // Check if this user already owns this username (re-registration edge case)
            if (existingUserId === userId) {
              console.log(`✅ Username "${normalizedUsername}" already owned by user ${userId}`);
              return; // Already owned, allow it
            }

            // Username taken by another user
            console.log(`❌ Username "${normalizedUsername}" already taken by user ${existingUserId}`);
            throw new HttpsError(
                "already-exists",
                `Username "${username}" is already taken`
            );
          }

          // Username available - claim it
          transaction.set(usernameDocRef, {
            userId: userId,
            usernameLowercase: normalizedUsername,
            usernameDisplay: username.trim(), // Preserve original casing for display
            claimedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`✅ Username "${normalizedUsername}" reserved for user ${userId}`);
        });

        return {
          success: true,
          username: normalizedUsername,
        };
      } catch (error) {
        // Re-throw HttpsError as-is
        if (error instanceof HttpsError) {
          throw error;
        }

        console.error("Username reservation error:", error);
        throw new HttpsError(
            "internal",
            "Failed to reserve username. Please try again."
        );
      }
    }
);

/**
 * P0-2: Validate username availability (read-only check)
 * Use this for real-time validation in the UI
 *
 * @param {string} username - The username to check
 * @returns {object} - {available: boolean}
 */
exports.checkUsernameAvailability = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    },
    async (request) => {
      const {username} = request.data;

      if (!username || typeof username !== "string") {
        throw new HttpsError("invalid-argument", "Username is required");
      }

      const normalizedUsername = username.trim().toLowerCase();

      // Validate format
      if (!/^[a-z0-9_]{3,20}$/.test(normalizedUsername)) {
        return {
          available: false,
          reason: "invalid_format",
          message: "Username must be 3-20 characters (letters, numbers, underscores only)",
        };
      }

      try {
        const db = admin.firestore();
        const usernameDoc = await db.collection("usernames")
            .doc(normalizedUsername)
            .get();

        const available = !usernameDoc.exists;

        console.log(`🔍 Username "${normalizedUsername}" availability: ${available ? "AVAILABLE" : "TAKEN"}`);

        return {
          available: available,
          username: normalizedUsername,
        };
      } catch (error) {
        console.error("Username availability check error:", error);
        throw new HttpsError("internal", "Failed to check username availability");
      }
    }
);

/**
 * Resolve a username to the account email so the client can call
 * signInWithEmailAndPassword without the email ever being stored
 * in a public Firestore document.
 *
 * Flow:
 *   1. Client sends { username }  (no password — never sent to the server)
 *   2. Function reads usernameLookup/{username} → gets { uid }
 *   3. Function calls admin.auth().getUser(uid) → gets email
 *   4. Returns { email } to the client
 *   5. Client calls Firebase Auth signInWithEmailAndPassword(email, password)
 *
 * This function is intentionally unauthenticated (no auth guard) so it can
 * be called before the user has a Firebase token. It does NOT return a token
 * or perform the sign-in itself, so it cannot be abused to bypass passwords.
 *
 * Rate-limiting note: Firebase App Check (enforced in production) + the fact
 * that we return only the email (not a token) keep abuse risk minimal.
 */
exports.resolveUsernameToEmail = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR // Allow pre-auth callers; App Check still blocks invalid apps
    },
    async (request) => {
      const {username} = request.data;

      if (!username || typeof username !== "string") {
        throw new HttpsError("invalid-argument", "username is required");
      }

      const normalizedUsername = username.trim().toLowerCase().replace(/^@/, "");

      if (!/^[a-z0-9_.]{1,30}$/.test(normalizedUsername)) {
        throw new HttpsError("invalid-argument", "Invalid username format");
      }

      const db = admin.firestore();

      // Step 1: look up the uid from the public (email-free) index
      const lookupDoc = await db
          .collection("usernameLookup")
          .doc(normalizedUsername)
          .get();

      let uid;

      if (lookupDoc.exists) {
        uid = lookupDoc.data()?.uid;
      } else {
        // Fallback: usernameLookup doc missing (account pre-dates the index).
        // Query the users collection directly by usernameLowercase field.
        console.log(`⚠️ resolveUsernameToEmail: no lookup doc for @${normalizedUsername} — falling back to users query`);
        const usersSnap = await db
            .collection("users")
            .where("usernameLowercase", "==", normalizedUsername)
            .limit(1)
            .get();

        if (usersSnap.empty) {
          throw new HttpsError("not-found", "Invalid username or password");
        }

        uid = usersSnap.docs[0].id;

        // Backfill the lookup doc so next login is fast
        try {
          await db.collection("usernameLookup").doc(normalizedUsername).set({uid});
          console.log(`✅ resolveUsernameToEmail: backfilled usernameLookup/@${normalizedUsername} → uid=${uid}`);
        } catch (backfillErr) {
          // Non-fatal — login will still succeed
          console.warn(`⚠️ resolveUsernameToEmail: backfill write failed (non-fatal):`, backfillErr);
        }
      }

      if (!uid) {
        throw new HttpsError("internal", "Malformed username record");
      }

      // Step 2: resolve uid → email via Admin SDK (never stored publicly)
      let userRecord;
      try {
        userRecord = await admin.auth().getUser(uid);
      } catch (err) {
        console.error(`resolveUsernameToEmail: getUser(${uid}) failed:`, err);
        throw new HttpsError("not-found", "Invalid username or password");
      }

      if (!userRecord.email) {
        // Account created via phone or anonymous — cannot sign in with password
        throw new HttpsError(
            "failed-precondition",
            "This account does not have a password. Please sign in another way."
        );
      }

      console.log(`✅ resolveUsernameToEmail: @${normalizedUsername} → uid=${uid}`);
      return {email: userRecord.email};
    }
);

/**
 * SECURE username sign-in (audit F-02).
 *
 * Replaces resolveUsernameToEmail for the sign-in path: the email NEVER leaves
 * the server. The client sends {username, password}; we resolve username → uid
 * → email server-side, verify the password against Identity Toolkit, and return
 * ONLY a Firebase custom token. The client then calls signIn(withCustomToken:).
 * This removes the per-username email-enumeration / PII-harvest vector.
 *
 * Requires the project Web API key in the FIREBASE_WEB_API_KEY env var (set via
 * `firebase functions:secrets:set FIREBASE_WEB_API_KEY` or functions config).
 *
 * @deprecated resolveUsernameToEmail — migrate clients to this and remove it.
 */
exports.signInWithUsername = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
      secrets: ["FIREBASE_WEB_API_KEY"],
    },
    async (request) => {
      const {username, password} = request.data || {};

      if (!username || typeof username !== "string" ||
          !password || typeof password !== "string") {
        throw new HttpsError("invalid-argument", "username and password are required");
      }

      const normalizedUsername = username.trim().toLowerCase().replace(/^@/, "");
      if (!/^[a-z0-9_.]{1,30}$/.test(normalizedUsername)) {
        // Generic message — never confirm whether the username exists.
        throw new HttpsError("unauthenticated", "Invalid username or password");
      }

      const apiKey = process.env.FIREBASE_WEB_API_KEY;
      if (!apiKey) {
        console.error("signInWithUsername: FIREBASE_WEB_API_KEY not configured");
        throw new HttpsError("internal", "Sign-in temporarily unavailable");
      }

      const db = admin.firestore();

      // Resolve username → uid (public, email-free index; same fallback as above)
      let uid;
      const lookupDoc = await db.collection("usernameLookup").doc(normalizedUsername).get();
      if (lookupDoc.exists) {
        uid = lookupDoc.data()?.uid;
      } else {
        const usersSnap = await db.collection("users")
            .where("usernameLowercase", "==", normalizedUsername)
            .limit(1).get();
        if (usersSnap.empty) {
          throw new HttpsError("unauthenticated", "Invalid username or password");
        }
        uid = usersSnap.docs[0].id;
        try {
          await db.collection("usernameLookup").doc(normalizedUsername).set({uid});
        } catch (_) { /* non-fatal backfill */ }
      }
      if (!uid) {
        throw new HttpsError("unauthenticated", "Invalid username or password");
      }

      // uid → email (Admin SDK; email stays server-side)
      let userRecord;
      try {
        userRecord = await admin.auth().getUser(uid);
      } catch (err) {
        throw new HttpsError("unauthenticated", "Invalid username or password");
      }
      if (!userRecord.email) {
        throw new HttpsError(
            "failed-precondition",
            "This account does not have a password. Please sign in another way.");
      }

      // Verify the password via Identity Toolkit WITHOUT returning the email.
      const resp = await fetch(
          `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
          {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({
              email: userRecord.email,
              password,
              returnSecureToken: false,
            }),
          });

      if (!resp.ok) {
        // Wrong password / disabled / etc. — always generic.
        throw new HttpsError("unauthenticated", "Invalid username or password");
      }

      const customToken = await admin.auth().createCustomToken(uid);
      console.log(`✅ signInWithUsername: @${normalizedUsername} → token minted for uid=${uid}`);
      return {customToken};
    }
);

/**
 * One-time backfill: populate usernameLookup for all existing users
 * that were created before the lookup index was introduced.
 * Call once from the Firebase console or CLI — safe to call multiple times (idempotent).
 * Restricted to admin callers only.
 */
exports.backfillUsernameLookup = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    },
    async (request) => {
      // SECURITY FIX (HIGH 2026-06-11): Previously only checked callerUid != null.
      // Any signed-in user could trigger a full users-collection scan, exposing all UIDs.
      // Now requires the admin custom claim (same guard as setAdminClaim and banUserPhone).
      if (!request.auth || request.auth.token.admin !== true) {
        throw new HttpsError("permission-denied", "Admin only.");
      }

      const db = admin.firestore();

      // Fetch all user documents in batches
      const usersSnap = await db.collection("users").get();
      let written = 0;
      let skipped = 0;
      const batch = db.batch();

      for (const doc of usersSnap.docs) {
        const data = doc.data();
        const username = (data.usernameLowercase || data.username || "").toLowerCase().trim();
        if (!username) {
          skipped++;
          continue;
        }

        const lookupRef = db.collection("usernameLookup").doc(username);
        batch.set(lookupRef, {uid: doc.id}, {merge: true});
        written++;
      }

      await batch.commit();
      console.log(`✅ backfillUsernameLookup: wrote ${written}, skipped ${skipped}`);
      return {written, skipped};
    }
);

/**
 * P0-2: Clean up username reservation when user document is deleted
 * Triggered automatically when users/{userId} is deleted
 */
exports.onUserDeleted = onDocumentDeleted(
    {
      document: "users/{userId}",
      region: "us-central1",
    },
    async (event) => {
      const userId = event.params.userId;
      const userData = event.data.data();

      console.log(`🗑️ User deleted: ${userId}`);

      try {
        const db = admin.firestore();
        const username = userData?.usernameLowercase || userData?.username?.toLowerCase();

        if (username) {
          // Release username for future use (audit F-04: also clear the
          // usernameLookup index, otherwise the username→uid record is orphaned
          // and the name can never be re-claimed).
          await Promise.all([
            db.collection("usernames").doc(username).delete(),
            db.collection("usernameLookup").doc(username).delete(),
          ]);
          console.log(`✅ Username "${username}" + lookup index released`);
        }

        // P0-3: CASCADE DELETE - Clean up all user data
        await cascadeDeleteUserData(userId);

        return {success: true};
      } catch (error) {
        console.error("Error in onUserDeleted:", error);
        // Don't throw - we want the user deletion to succeed even if cleanup fails
        return null;
      }
    }
);

/**
 * P0-3: Cascade delete all user data when account is deleted
 *
 * Deletes:
 * - All posts by the user
 * - All comments by the user (Realtime Database)
 * - All follows (following/followers relationships)
 * - All conversations where user is the only participant
 * - User's messages in conversations (marks as deleted)
 * - All notifications sent by the user
 * - All notifications received by the user
 * - Profile images from Storage
 * - Username reservation
 * - Saved posts
 * - Prayer requests
 * - Church notes
 *
 * @param {string} userId - The user ID to delete data for
 */
async function cascadeDeleteUserData(userId) {
  console.log(`🧹 Starting cascade delete for user ${userId}`);

  const db = admin.firestore();
  const rtdb = admin.database();
  const storage = admin.storage();

  try {
    // 1. Delete all posts by user
    console.log("1️⃣ Deleting posts...");
    const postsSnapshot = await db.collection("posts")
        .where("userId", "==", userId)
        .get();

    const postDeletePromises = [];
    postsSnapshot.forEach((doc) => {
      postDeletePromises.push(doc.ref.delete());
      console.log(`   Deleting post: ${doc.id}`);
    });
    await Promise.all(postDeletePromises);
    console.log(`✅ Deleted ${postsSnapshot.size} posts`);

    // 2. Delete all comments by user from Realtime Database
    console.log("2️⃣ Deleting comments from Realtime Database...");
    const commentsRef = rtdb.ref("postInteractions");
    const commentsSnapshot = await commentsRef.once("value");

    const commentDeletePromises = [];
    if (commentsSnapshot.exists()) {
      commentsSnapshot.forEach((postSnap) => {
        const comments = postSnap.child("comments").val();
        if (comments) {
          Object.entries(comments).forEach(([commentId, comment]) => {
            if (comment.userId === userId) {
              const deleteRef = rtdb.ref(`postInteractions/${postSnap.key}/comments/${commentId}`);
              commentDeletePromises.push(deleteRef.remove());
              console.log(`   Deleting comment: ${commentId}`);
            }
          });
        }
      });
    }
    await Promise.all(commentDeletePromises);
    console.log(`✅ Deleted ${commentDeletePromises.length} comments`);

    // 3. Delete follow relationships
    console.log("3️⃣ Deleting follow relationships...");

    // Delete where user is following others
    const followingSnapshot = await db.collection("follows")
        .where("followerId", "==", userId)
        .get();
    const followingDeletePromises = followingSnapshot.docs.map((doc) => doc.ref.delete());

    // Delete where others are following user
    const followersSnapshot = await db.collection("follows")
        .where("followingId", "==", userId)
        .get();
    const followersDeletePromises = followersSnapshot.docs.map((doc) => doc.ref.delete());

    await Promise.all([...followingDeletePromises, ...followersDeletePromises]);
    console.log(`✅ Deleted ${followingSnapshot.size + followersSnapshot.size} follow relationships`);

    // 4. Handle conversations
    console.log("4️⃣ Handling conversations...");
    const conversationsSnapshot = await db.collection("conversations")
        .where("participantIds", "array-contains", userId)
        .get();

    const conversationPromises = [];
    conversationsSnapshot.forEach((doc) => {
      const data = doc.data();
      const participantIds = data.participantIds || [];

      if (participantIds.length <= 2) {
        // 1-on-1 conversation - delete entire conversation
        conversationPromises.push(doc.ref.delete());
        console.log(`   Deleting 1-on-1 conversation: ${doc.id}`);
      } else {
        // Group conversation - just remove user from participants
        const updatedParticipants = participantIds.filter((id) => id !== userId);
        conversationPromises.push(doc.ref.update({
          participantIds: updatedParticipants,
        }));
        console.log(`   Removing user from group conversation: ${doc.id}`);
      }
    });
    await Promise.all(conversationPromises);
    console.log(`✅ Handled ${conversationsSnapshot.size} conversations`);

    // 5. Delete all notifications sent by user (to other users)
    console.log("5️⃣ Deleting notifications sent by user...");
    const usersSnapshot = await db.collection("users").get();
    const notificationDeletePromises = [];

    for (const userDoc of usersSnapshot.docs) {
      const notificationsSnapshot = await userDoc.ref
          .collection("notifications")
          .where("actorId", "==", userId)
          .get();

      notificationsSnapshot.forEach((notifDoc) => {
        notificationDeletePromises.push(notifDoc.ref.delete());
      });
    }
    await Promise.all(notificationDeletePromises);
    console.log(`✅ Deleted ${notificationDeletePromises.length} notifications sent by user`);

    // 6. Delete all notifications received by user
    console.log("6️⃣ Deleting notifications received by user...");
    const userNotificationsSnapshot = await db.collection("users")
        .doc(userId)
        .collection("notifications")
        .get();

    const userNotifDeletePromises = userNotificationsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(userNotifDeletePromises);
    console.log(`✅ Deleted ${userNotifDeletePromises.length} notifications received by user`);

    // 7. Delete saved posts
    console.log("7️⃣ Deleting saved posts...");
    const savedPostsSnapshot = await db.collection("users")
        .doc(userId)
        .collection("savedPosts")
        .get();

    const savedPostsDeletePromises = savedPostsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(savedPostsDeletePromises);
    console.log(`✅ Deleted ${savedPostsSnapshot.size} saved posts`);

    // 8. Delete prayer requests
    console.log("8️⃣ Deleting prayer requests...");
    const prayersSnapshot = await db.collection("prayers")
        .where("userId", "==", userId)
        .get();

    const prayersDeletePromises = prayersSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(prayersDeletePromises);
    console.log(`✅ Deleted ${prayersSnapshot.size} prayer requests`);

    // 9. Delete church notes
    console.log("9️⃣ Deleting church notes...");
    const notesSnapshot = await db.collection("churchNotes")
        .where("userId", "==", userId)
        .get();

    const notesDeletePromises = notesSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(notesDeletePromises);
    console.log(`✅ Deleted ${notesSnapshot.size} church notes`);

    // 10. Delete profile images from Storage
    console.log("🔟 Deleting profile images from Storage...");
    try {
      const bucket = storage.bucket();
      const profileImagePaths = [
        `profile_images/${userId}.jpg`,
        `profile_images/${userId}.jpeg`,
        `profile_images/${userId}.png`,
        `profile_images/${userId}_thumb.jpg`,
        `profile_images/${userId}_thumb.jpeg`,
        `profile_images/${userId}_thumb.png`,
      ];

      const storageDeletePromises = profileImagePaths.map(async (path) => {
        try {
          await bucket.file(path).delete();
          console.log(`   Deleted: ${path}`);
        } catch (error) {
          // File might not exist, that's okay
          if (error.code !== 404) {
            console.log(`   Could not delete ${path}: ${error.message}`);
          }
        }
      });

      await Promise.all(storageDeletePromises);
      console.log("✅ Storage cleanup complete");
    } catch (storageError) {
      console.error("Storage deletion error (non-critical):", storageError);
    }

    // 11. Delete reposts by user
    console.log("1️⃣1️⃣ Deleting reposts...");
    const repostsSnapshot = await db.collection("reposts")
        .where("userId", "==", userId)
        .get();
    const repostsDeletePromises = repostsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(repostsDeletePromises);
    console.log(`✅ Deleted ${repostsSnapshot.size} reposts`);

    // 12. Delete block records where user is the blocker
    console.log("1️⃣2️⃣ Deleting block records...");
    const blocksSnapshot = await db.collection("blocks")
        .where("blockerId", "==", userId)
        .get();
    const blocksBlockedSnapshot = await db.collection("blocks")
        .where("blockedId", "==", userId)
        .get();
    const blocksDeletePromises = [
      ...blocksSnapshot.docs.map((doc) => doc.ref.delete()),
      ...blocksBlockedSnapshot.docs.map((doc) => doc.ref.delete()),
    ];
    await Promise.all(blocksDeletePromises);
    console.log(`✅ Deleted ${blocksDeletePromises.length} block records`);

    // 13. Delete top-level savedPosts collection entries
    console.log("1️⃣3️⃣ Deleting top-level saved posts...");
    const topSavedPostsSnapshot = await db.collection("savedPosts")
        .where("userId", "==", userId)
        .get();
    const topSavedDeletePromises = topSavedPostsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(topSavedDeletePromises);
    console.log(`✅ Deleted ${topSavedPostsSnapshot.size} top-level saved posts`);

    // 14. Delete user's feed preferences and signals
    console.log("1️⃣4️⃣ Deleting feed preferences...");
    await Promise.all([
      db.collection("userFeedPrefs").doc(userId).delete().catch(() => {}),
      db.collection("userFeedSignals").doc(userId).delete().catch(() => {}),
      db.collection("userSafetyRecords").doc(userId).delete().catch(() => {}),
      db.collection("datingProfiles").doc(userId).delete().catch(() => {}),
      db.collection("userRestrictions").doc(userId).delete().catch(() => {}),
    ]);
    console.log("✅ Cleaned up feed preferences and profile data");

    // 15. Delete the user document itself
    console.log("1️⃣5️⃣ Deleting user document...");
    // Note: this is triggered by user document deletion, so the doc is already gone
    // But clean up the users/{userId} subcollections explicitly
    const userSubcollections = [
      "following", "followers", "savedPosts", "blockedUsers", "notifications",
      "devices", "usageSessions", "wellnessEvents", "scrollBudgetUsage",
    ];
    for (const subcol of userSubcollections) {
      const subSnap = await db.collection("users").doc(userId).collection(subcol).get();
      const subDeletes = subSnap.docs.map((d) => d.ref.delete());
      await Promise.all(subDeletes);
      if (subSnap.size > 0) console.log(`   Deleted ${subSnap.size} docs from users/${userId}/${subcol}`);
    }
    console.log("✅ User subcollections cleaned up");

    console.log(`✅✅✅ CASCADE DELETE COMPLETE for user ${userId} ✅✅✅`);
    console.log("Summary:");
    console.log(`- Posts deleted: ${postsSnapshot.size}`);
    console.log(`- Comments deleted: ${commentDeletePromises.length}`);
    console.log(`- Follow relationships: ${followingSnapshot.size + followersSnapshot.size}`);
    console.log(`- Conversations handled: ${conversationsSnapshot.size}`);
    console.log(`- Notifications deleted: ${notificationDeletePromises.length + userNotifDeletePromises.length}`);
    console.log(`- Saved posts: ${savedPostsSnapshot.size + topSavedPostsSnapshot.size}`);
    console.log(`- Prayers: ${prayersSnapshot.size}`);
    console.log(`- Church notes: ${notesSnapshot.size}`);
    console.log(`- Reposts: ${repostsSnapshot.size}`);
    console.log(`- Block records: ${blocksDeletePromises.length}`);

    return {success: true};
  } catch (error) {
    console.error("❌ Error in cascadeDeleteUserData:", error);
    throw error;
  }
}

/**
 * P0-3: Manually trigger cascade delete (for admin use)
 * Use this to clean up orphaned data or test the cascade delete logic
 */
exports.manualCascadeDelete = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    },
    async (request) => {
      const {userId} = request.data;
      const requesterId = request.auth?.uid;

      console.log(`🗑️ Manual cascade delete request for user ${userId}`);

      // Validate authentication
      if (!requesterId) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      // Security: Only allow users to delete their own data
      // In production, you might want admin-only access
      if (requesterId !== userId) {
        throw new HttpsError(
            "permission-denied",
            "You can only delete your own data"
        );
      }

      if (!userId) {
        throw new HttpsError("invalid-argument", "userId is required");
      }

      try {
        // 1. Cascade all Firestore/RTDB/Storage data (also releases the
        //    username + usernameLookup via the users/{uid} delete trigger).
        await cascadeDeleteUserData(userId);

        // 2. Audit F-04: make the SERVER authoritative. Revoke all refresh
        //    tokens (immediately invalidating existing sessions) and delete the
        //    Auth user here, rather than relying on a client-driven
        //    currentUser.delete() that can leave a partial wipe on a mid-flow
        //    network drop. Token revoke + delete is idempotent enough that a
        //    client that still calls delete() simply sees user-not-found.
        try {
          await admin.auth().revokeRefreshTokens(userId);
        } catch (revokeErr) {
          console.warn("manualCascadeDelete: revokeRefreshTokens failed (non-fatal):", revokeErr);
        }
        try {
          await admin.auth().deleteUser(userId);
          console.log(`✅ Auth user ${userId} deleted server-side`);
        } catch (authErr) {
          if (authErr?.code === "auth/user-not-found") {
            console.log(`ℹ️ Auth user ${userId} already deleted`);
          } else {
            throw authErr;
          }
        }

        return {
          success: true,
          message: "User data cascade delete completed successfully",
        };
      } catch (error) {
        console.error("Manual cascade delete error:", error);
        throw new HttpsError(
            "internal",
            "Failed to delete user data. Please contact support."
        );
      }
    }
);

// Export the cascade delete function for use in other functions
exports.cascadeDeleteUserData = cascadeDeleteUserData;

// ============================================================================
// P0-2: SERVER-SET AGE TIER ON USER DOCUMENT CREATION
// ============================================================================
// Triggers whenever a user document is created in Firestore.
// Reads the client-supplied `birthYear` field and writes the server-computed
// `ageTier` back via admin SDK (which bypasses client-writeable fields rules).
//
// Tier mapping:
//   blocked  — birth year implies age < 13  (COPPA hard block)
//   tierB    — 13–15
//   tierC    — 16–17
//   tierD    — 18+
// Missing, malformed, or out-of-range birth years fail closed to blocked.
// ============================================================================

const {onDocumentCreated: onDocCreated} = require("firebase-functions/v2/firestore");

// GAP P0-11: computeAgeTier moved to the shared ./ageTier module so production and
// the COPPA unit test import the SAME function instead of a forked copy.
const {computeAgeTier} = require("./ageTier");
exports.computeAgeTier = computeAgeTier;

exports.onUserDocCreated = onDocCreated(
    {
      document: "users/{userId}",
      region: "us-central1",
    },
    async (event) => {
      const userId = event.params.userId;
      const data = event.data?.data();

      if (!data) {
        console.warn(`[ageTier] Empty user document created for ${userId} — skipping`);
        return null;
      }

      // H-03: Check if the phone number used for registration is banned.
      // phoneNumber is written to the user doc by the client during sign-up.
      // If banned, delete the newly-created user document so the account
      // cannot be used, and disable the Auth account.
      const phoneNumber = data.phoneNumber || null;
      if (phoneNumber) {
        try {
          await checkPhoneNotBanned(phoneNumber);
        } catch (banErr) {
          console.warn(`[banCheck] Banned phone attempted registration: userId=${userId}`);
          // Disable the Firebase Auth account to prevent sign-in
          try {
            await admin.auth().updateUser(userId, {disabled: true});
          } catch (authErr) {
            console.error(`[banCheck] Failed to disable Auth account ${userId}:`, authErr);
          }
          // Delete the Firestore user document so the account has no profile
          try {
            await admin.firestore().collection("users").doc(userId).delete();
          } catch (fsErr) {
            console.error(`[banCheck] Failed to delete user doc ${userId}:`, fsErr);
          }
          return null;
        }
      }

      const birthYear = data.birthYear;
      const currentYear = new Date().getFullYear();
      const ageTier = computeAgeTier(birthYear, currentYear);

      console.log(`[ageTier] userId=${userId} ageTier=${ageTier}`) // GAP A7-P1 birthYear redacted from logs;

      const updateFields = {
        ageTier,
        ageTierSetAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // M-03: Minors must always have content filtering set to restricted.
      if (ageTier === "tierB" || ageTier === "tierC") {
        updateFields.sensitiveContentLevel = "restricted";
      }

      try {
        await admin.firestore()
            .collection("users")
            .doc(userId)
            .update(updateFields);
        console.log(`✅ [ageTier] Set ageTier="${ageTier}" for user ${userId}`);
      } catch (err) {
        console.error(`❌ [ageTier] Failed to set ageTier for ${userId}:`, err);
        // Non-fatal: AgeAssuranceService on the client defaults to tierB (fail-safe)
        // when ageTier is absent, so missing tier ≠ full access.
      }

      return null;
    }
);

// ============================================================================
// SESSION INVALIDATION — revoke all refresh tokens for the calling user.
// Called by the iOS client during sign-out to force all other devices to
// re-authenticate on their next request. Without this, a stolen device
// retains a valid session for up to 1 hour (Firebase ID token TTL).
// ============================================================================

exports.revokeUserSessions = onCall(
    {region: "us-central1", enforceAppCheck: true}, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be authenticated.");
      }

      const uid = request.auth.uid;

      try {
        // Revoke all Firebase refresh tokens for this user.
        // All existing sessions on other devices will fail on next token refresh.
        await admin.auth().revokeRefreshTokens(uid);
        console.log(`✅ [revokeUserSessions] Refresh tokens revoked for ${uid}`);
        return {success: true};
      } catch (err) {
        console.error(`❌ [revokeUserSessions] Failed for ${uid}:`, err);
        throw new HttpsError("internal", "Failed to revoke sessions.");
      }
    }
);

/**
 * Set admin Custom Claim on a user.
 * Only callable by users who already have the admin claim.
 * This prevents any user from escalating themselves to admin.
 *
 * Usage (from Firebase console or admin tool):
 *   functions.httpsCallable("setAdminClaim").call({ targetUid: "...", grant: true })
 */
exports.setAdminClaim = onCall(
    {region: "us-central1", enforceAppCheck: true}, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    async (request) => {
      // Only existing admins can grant or revoke admin status
      if (!request.auth || request.auth.token.admin !== true) {
        throw new HttpsError(
            "permission-denied",
            "Only admins can modify admin claims."
        );
      }

      const {targetUid, grant} = request.data;
      if (!targetUid || typeof grant !== "boolean") {
        throw new HttpsError("invalid-argument", "targetUid (string) and grant (boolean) are required.");
      }

      // Prevent self-modification
      if (targetUid === request.auth.uid) {
        throw new HttpsError("invalid-argument", "Admins cannot modify their own claim.");
      }

      try {
        // Get existing custom claims to avoid overwriting other claims
        const user = await admin.auth().getUser(targetUid);
        const existingClaims = user.customClaims || {};
        const updatedClaims = {...existingClaims, admin: grant};

        await admin.auth().setCustomUserClaims(targetUid, updatedClaims);
        console.log(`✅ [setAdminClaim] admin=${grant} set for ${targetUid} by ${request.auth.uid}`);

        // Force token refresh so the new claim takes effect on next request
        await admin.auth().revokeRefreshTokens(targetUid);

        return {success: true, targetUid, admin: grant};
      } catch (err) {
        console.error(`❌ [setAdminClaim] Failed for ${targetUid}:`, err);
        throw new HttpsError("internal", "Failed to set admin claim.");
      }
    }
);

/**
 * Bootstrap the very first admin from the Firebase console or Admin SDK.
 * This function can ONLY be called via the Firebase Admin SDK (server-to-server) —
 * it is NOT a callable function. Run it once during initial platform setup:
 *
 *   const admin = require('firebase-admin');
 *   admin.initializeApp();
 *   admin.auth().setCustomUserClaims('<your-uid>', { admin: true });
 *
 * After the first admin is set, use setAdminClaim() to manage subsequent admins.
 */

// ============================================================================
// H-03: banUserPhone — Admin-only callable
// Hashes the target user's phone number and writes it to bannedPhones/{hash}.
// Future registration attempts using the same phone will be blocked by
// checkPhoneNotBanned() in onUserDocCreated.
//
// TODO: Wire this into the accountSuspension flow so that banning a user
// automatically bans their phone number. Example call site:
//   await admin.functions().httpsCallable("banUserPhone")({ userId: bannedUid });
// ============================================================================

exports.banUserPhone = onCall(
    {region: "us-central1", enforceAppCheck: true}, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    async (request) => {
      // Admin-only: caller must have the admin custom claim
      if (!request.auth || request.auth.token.admin !== true) {
        throw new HttpsError(
            "permission-denied",
            "Only admins can ban phone numbers."
        );
      }

      const {userId} = request.data;
      if (!userId || typeof userId !== "string") {
        throw new HttpsError("invalid-argument", "userId (string) is required.");
      }

      const adminUid = request.auth.uid;

      // Look up the user's phone number from Firebase Auth
      let userRecord;
      try {
        userRecord = await admin.auth().getUser(userId);
      } catch (err) {
        console.error(`[banUserPhone] getUser(${userId}) failed:`, err);
        throw new HttpsError("not-found", "User not found.");
      }

      const phoneNumber = userRecord.phoneNumber || null;
      if (!phoneNumber) {
        // Account has no phone number — nothing to ban on that dimension.
        console.warn(`[banUserPhone] User ${userId} has no phone number — skipping phone ban.`);
        return {success: true, phoneNumber: null, note: "no_phone_number"};
      }

      const hashedPhone = hashPhoneNumber(phoneNumber);

      await admin.firestore().collection("bannedPhones").doc(hashedPhone).set({
        hashedPhone,
        bannedAt: admin.firestore.FieldValue.serverTimestamp(),
        bannedBy: adminUid,
        userId,
        reason: "ban_evasion_prevention",
      });

      console.log(`[banUserPhone] Phone banned for userId=${userId} by admin=${adminUid}`);
      return {success: true, userId, hashedPhone};
    }
);

// ============================================================================
// M-02: UPDATE BIRTH YEAR — server-enforced age-downgrade protection.
// Adults (tierD) cannot re-declare as minors without moderator review.
// Tier order (ascending privilege): blocked < tierB < tierC < tierD
// ============================================================================

const TIER_ORDER = ["blocked", "tierB", "tierC", "tierD"];

exports.updateBirthYear = onCall(
    {region: "us-central1", enforceAppCheck: true}, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be authenticated.");
      }

      const uid = request.auth.uid;
      const {birthYear} = request.data || {};

      if (!birthYear || typeof birthYear !== "number" || birthYear < 1900 || birthYear > new Date().getFullYear()) {
        throw new HttpsError("invalid-argument", "A valid birthYear (number) is required.");
      }

      const db = admin.firestore();
      const userDoc = await db.collection("users").doc(uid).get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User document not found.");
      }

      const existingData = userDoc.data();
      const currentTier = existingData.ageTier || "blocked";
      const currentYear = new Date().getFullYear();
      const newTier = computeAgeTier(birthYear, currentYear);

      // M-02: Prevent age downgrade. Adults cannot re-declare as minors.
      if (TIER_ORDER.indexOf(newTier) < TIER_ORDER.indexOf(currentTier)) {
        console.warn(`[updateBirthYear] Downgrade attempt uid=${uid} ${currentTier} -> ${newTier}`);
        throw new HttpsError(
            "permission-denied",
            "Age changes that reduce your age tier require moderator review."
        );
      }

      await db.collection("users").doc(uid).update({
        birthYear,
        ageTier: newTier,
        ageTierSetAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[updateBirthYear] uid=${uid} ageTier=${newTier}`) // GAP A7-P1 birthYear redacted from logs;
      return {success: true, ageTier: newTier};
    }
);
