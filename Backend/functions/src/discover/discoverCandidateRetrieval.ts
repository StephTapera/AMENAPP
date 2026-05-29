import * as admin from "firebase-admin";
import { DiscoverItemDoc } from "./discoverTypes";

export async function retrieveDiscoverCandidates(limit = 120): Promise<DiscoverItemDoc[]> {
  const db = admin.firestore();

  const snapshot = await db.collection("discoverItems").limit(limit).get();
  if (!snapshot.empty) {
    return snapshot.docs.map((doc) => {
      const data = doc.data() as Omit<DiscoverItemDoc, "id">;
      return { ...data, id: doc.id };
    });
  }

  // Fallback: surface recent public posts from the OpenTable feed as discover candidates.
  // This runs until the discoverItems collection is seeded with curated content.
  const postsSnap = await db
    .collection("posts")
    .where("isDeleted", "!=", true)
    .orderBy("isDeleted")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return postsSnap.docs
    .filter((doc) => {
      const d = doc.data();
      return d.visibility !== "private" && !d.isDeleted;
    })
    .map((doc) => {
      const d = doc.data();
      const author = d.authorId
        ? {
            id: String(d.authorId),
            name: String(d.authorDisplayName ?? "Community Member"),
            avatarURL: d.authorProfileImageURL ?? undefined,
          }
        : undefined;

      return {
        id: doc.id,
        type: "prayerSafePost" as const,
        title: String(d.caption ?? d.text ?? "").slice(0, 120) || "Faith reflection",
        subtitle: undefined,
        sourceId: doc.id,
        sourceType: "post",
        author,
        topics: Array.isArray(d.hashtags) ? d.hashtags : [],
        scriptureRefs: [],
        badges: [],
        createdAt: d.createdAt ?? admin.firestore.Timestamp.now(),
        discoverVisibility: "public" as const,
      } satisfies DiscoverItemDoc;
    });
}
