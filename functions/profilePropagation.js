/**
 * profilePropagation.js
 *
 * When a user changes their displayName, username, or profileImageURL,
 * this trigger propagates the new values to all denormalized copies stored
 * on their posts and comments so cached data doesn't go stale.
 *
 * Fields propagated:
 *   posts:    authorName, authorUsername, authorProfileImageURL, authorInitials
 *   comments: authorName, authorUsername, authorProfileImageURL, authorInitials
 *
 * SECURITY (H8 fix): displayName and bio are screened through NeMo Guard before
 * propagation. Unsafe values are reverted to the prior value and a moderationQueue
 * entry is created. The trigger fails closed: a NIM error is treated as unsafe.
 */

const admin = require("firebase-admin");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

/**
 * Calls NeMo Guard and returns { safe: boolean, categories: string[] }.
 * Fails closed on any error (network failure, non-OK status, parse error).
 *
 * @param {string} text
 * @returns {Promise<{safe: boolean, categories: string[]}>}
 */
async function moderateText(text) {
  const apiKey = process.env.NVIDIA_API_KEY;
  const delays = [500, 1000, 2000];
  let res = null;

  for (let attempt = 0; attempt <= 3; attempt++) {
    try {
      res = await fetch(NIM_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: SAFETY_MODEL,
          messages: [{role: "user", content: text}],
          max_tokens: 100,
          temperature: 0,
        }),
      });
    } catch (err) {
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      // Network-level failure — fail closed.
      console.error("[profilePropagation] moderateText NIM fetch failed:", err.message);
      return {safe: false, categories: ["network_error"]};
    }

    if (res.status === 429 || res.status >= 500) {
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      console.error("[profilePropagation] moderateText NIM status:", res.status);
      return {safe: false, categories: [`nim_${res.status}`]};
    }
    break;
  }

  if (!res || !res.ok) {
    console.error("[profilePropagation] moderateText NIM non-OK:", res ? res.status : "no response");
    return {safe: false, categories: ["nim_error"]};
  }

  let data;
  try {
    data = await res.json();
  } catch {
    return {safe: false, categories: ["parse_error"]};
  }

  const raw = data.choices?.[0]?.message?.content ?? "";

  // Jailbreak-resistant parsing — fail closed on any ambiguity.
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
      const safe = String(parsed["User Safety"]).trim().toLowerCase() === "safe";
      const categories = parsed["Safety Categories"]
        ? String(parsed["Safety Categories"]).split(",").map((c) => c.trim().toLowerCase()).filter(Boolean)
        : [];
      return {safe, categories};
    }
    return {safe: false, categories: []};
  } catch {
    return {safe: false, categories: ["parse_error"]};
  }
}

const REGION = "us-central1";

/** Derive initials from a display name (up to 2 chars). */
function makeInitials(displayName) {
  if (!displayName) return "?";
  const parts = displayName.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/**
 * onUserProfileUpdated
 *
 * Triggered whenever a user document changes. Runs a batch update on
 * all posts authored by that user if any of the three key fields changed.
 * Comments are stored in RTDB indexed by postId, so we update them via
 * a separate RTDB write batch.
 *
 * Firestore batches are capped at 500 writes; for large accounts a second
 * pass is queued recursively.
 */
exports.onUserProfileUpdated = onDocumentUpdated(
    {
      document: "users/{userId}",
      region: REGION,
      secrets: [NVIDIA_API_KEY],
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      const userId = event.params.userId;

      // Determine which denormalized fields changed
      const nameChanged = before.displayName !== after.displayName;
      const usernameChanged = before.username !== after.username;
      const imageChanged = before.profileImageURL !== after.profileImageURL;
      const bioChanged = before.bio !== after.bio;

      if (!nameChanged && !usernameChanged && !imageChanged && !bioChanged) {
        return; // Nothing relevant changed
      }

      const db = admin.firestore();

      // ── SECURITY (H8): Moderate displayName and bio before propagation ──────
      // If either field is unsafe: revert the field to its prior value on the
      // user document and enqueue a moderation review. Never propagate unsafe
      // profile text to denormalized copies. Fails closed on NIM errors.
      const profileRevertFields = {};
      const profileModerationFlags = [];

      if (nameChanged && after.displayName) {
        const nameResult = await moderateText(after.displayName);
        if (!nameResult.safe) {
          console.warn(
              `[profilePropagation] displayName unsafe for userId=${userId}`,
              nameResult.categories,
          );
          profileRevertFields.displayName = before.displayName ?? "";
          profileModerationFlags.push({
            field: "displayName",
            value: after.displayName,
            categories: nameResult.categories,
          });
        }
      }

      if (bioChanged && after.bio) {
        const bioResult = await moderateText(after.bio);
        if (!bioResult.safe) {
          console.warn(
              `[profilePropagation] bio unsafe for userId=${userId}`,
              bioResult.categories,
          );
          profileRevertFields.bio = before.bio ?? "";
          profileModerationFlags.push({
            field: "bio",
            value: after.bio,
            categories: bioResult.categories,
          });
        }
      }

      if (Object.keys(profileRevertFields).length > 0) {
        // Revert unsafe fields and add a moderationQueue entry atomically.
        const revertBatch = db.batch();
        revertBatch.update(event.data.after.ref, {
          ...profileRevertFields,
          "moderation.profileLastFlagged": admin.firestore.FieldValue.serverTimestamp(),
          "moderation.profileFlaggedFields": profileModerationFlags.map((f) => f.field),
        });
        const queueRef = db.collection("moderationQueue").doc();
        revertBatch.set(queueRef, {
          contentRef: `users/${userId}`,
          contentType: "profile_field",
          authorId: userId,
          flaggedFields: profileModerationFlags,
          status: "pending",
          priority: "normal",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000),
        });
        await revertBatch.commit();
        console.log(`[profilePropagation] Reverted unsafe profile fields for ${userId}:`, profileModerationFlags.map((f) => f.field));
      }

      // Use the (possibly reverted) values for propagation.
      // Re-read from Firestore is not needed: if reverted, use before values directly.
      const safeDisplayName = profileRevertFields.displayName !== undefined
        ? profileRevertFields.displayName
        : (after.displayName ?? before.displayName ?? "");
      const effectiveNameChanged = nameChanged && profileRevertFields.displayName === undefined;

      const newDisplayName = safeDisplayName;
      const newUsername = after.username ?? before.username ?? "";
      const newImageURL = after.profileImageURL ?? null;
      const newInitials = makeInitials(newDisplayName);

      // Build the update payload for Firestore posts.
      // Use effectiveNameChanged: only propagate if the new displayName passed moderation
      // (i.e., was not reverted). Reverted names stay at the prior value and must not
      // overwrite existing denormalized copies.
      const postUpdate = {};
      if (effectiveNameChanged) {
        postUpdate.authorName = newDisplayName;
        postUpdate.authorInitials = newInitials;
      }
      if (usernameChanged) postUpdate.authorUsername = newUsername;
      if (imageChanged) postUpdate.authorProfileImageURL = newImageURL;

      console.log(
          `[profilePropagation] userId=${userId} fields changed:`,
          {effectiveNameChanged, usernameChanged, imageChanged, bioChanged},
      );

      // ── Propagate to Firestore posts ──────────────────────────────────────
      let lastDoc = null;
      let totalUpdated = 0;

      do {
        let query = db.collection("posts")
            .where("authorId", "==", userId)
            .orderBy("createdAt", "desc")
            .limit(400); // Stay under 500-write batch cap

        if (lastDoc) query = query.startAfter(lastDoc);

        const snap = await query.get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.update(doc.ref, postUpdate));
        await batch.commit();

        totalUpdated += snap.docs.length;
        lastDoc = snap.docs[snap.docs.length - 1];

        console.log(`[profilePropagation] Updated ${totalUpdated} posts so far for ${userId}`);
      } while (lastDoc && totalUpdated % 400 === 0);

      // ── Propagate to Firestore reposts (originalAuthor fields unchanged;
      //    only the reposting author's denormalized fields need updating) ──────
      // Already covered by the posts query above since reposts are in /posts.

      // ── Propagate to RTDB comments ────────────────────────────────────────
      // RTDB structure: postInteractions/{postId}/comments/{commentId}
      // We can't query all comments by userId directly in RTDB without a full scan.
      // Strategy: query Firestore posts by authorId to get postIds, then update
      // comments within those posts. For non-own-post comments, the user's comment
      // data is embedded and requires a full scan — we use the Firestore commentIndex
      // subcollection if it exists, otherwise skip (acceptable trade-off).
      try {
        const rtdb = admin.database();

        // Use a Firestore commentIndex if available (optional optimization)
        const commentIndexSnap = await db
            .collectionGroup("commentIndex")
            .where("authorId", "==", userId)
            .limit(500)
            .get();

        if (!commentIndexSnap.empty) {
          const rtdbUpdates = {};
          commentIndexSnap.docs.forEach((doc) => {
            const {postId, commentId} = doc.data();
            const basePath = `postInteractions/${postId}/comments/${commentId}`;
            if (effectiveNameChanged) {
              rtdbUpdates[`${basePath}/authorName`] = newDisplayName;
              rtdbUpdates[`${basePath}/authorInitials`] = newInitials;
            }
            if (usernameChanged) rtdbUpdates[`${basePath}/authorUsername`] = newUsername;
            if (imageChanged) rtdbUpdates[`${basePath}/authorProfileImageURL`] = newImageURL;
          });

          if (Object.keys(rtdbUpdates).length > 0) {
            await rtdb.ref().update(rtdbUpdates);
            console.log(`[profilePropagation] Updated ${commentIndexSnap.size} RTDB comments for ${userId}`);
          }
        } else {
          console.log(`[profilePropagation] No RTDB commentIndex found for ${userId} — skipping comment propagation`);
        }
      } catch (rtdbErr) {
        // Non-fatal: RTDB comment propagation failing is acceptable since
        // comments will show correct data on next full load from Firestore.
        console.warn(`[profilePropagation] RTDB comment update failed (non-fatal):`, rtdbErr.message);
      }

      console.log(`[profilePropagation] Done. Total Firestore posts updated: ${totalUpdated}`);
    },
);
