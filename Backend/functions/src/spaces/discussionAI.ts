// spaces/discussionAI.ts
// Space discussion CRUD + AI-generated discussion threads.
//
// Callables:
//   getSpaceDiscussions         — paginated discussion list for a space
//   createSpaceDiscussion       — create a new discussion thread
//   generateDiscussionFromContent — AI generates a starter discussion from a content item

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

interface GetSpaceDiscussionsInput {
    spaceId: string;
    limit?: number;
}

interface CreateSpaceDiscussionInput {
    spaceId: string;
    title: string;
    body: string;
    category: string;
}

interface GenerateDiscussionFromContentInput {
    spaceId: string;
    contentId: string;
    contentType: "livestream" | "podcast" | "video" | "post" | "bibleStudy";
}

interface DiscussionDoc {
    id: string;
    title: string;
    authorFirstName: string;
    category: string;
    replyCount: number;
    isPinned: boolean;
    isAIGenerated: boolean;
    lastActivityAt: string;
}

export const getSpaceDiscussions = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<DiscussionDoc[]> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const input = request.data as GetSpaceDiscussionsInput;
        if (!input.spaceId) throw new HttpsError("invalid-argument", "spaceId required.");

        const db = getFirestore();
        const limit = Math.min(input.limit ?? 30, 50);

        const snap = await db
            .collection(`spaces/${input.spaceId}/discussions`)
            .orderBy("isPinned", "desc")
            .orderBy("lastActivityAt", "desc")
            .limit(limit)
            .get();

        return snap.docs.map(doc => {
            const d = doc.data();
            return {
                id: doc.id,
                title: d.title ?? "",
                authorFirstName: d.authorFirstName ?? "Member",
                category: d.category ?? "general",
                replyCount: d.replyCount ?? 0,
                isPinned: d.isPinned ?? false,
                isAIGenerated: d.isAIGenerated ?? false,
                lastActivityAt: (d.lastActivityAt as Timestamp)?.toDate().toISOString() ?? new Date().toISOString(),
            };
        });
    }
);

export const createSpaceDiscussion = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<DiscussionDoc> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const input = request.data as CreateSpaceDiscussionInput;
        if (!input.spaceId) throw new HttpsError("invalid-argument", "spaceId required.");
        if (!input.title || input.title.trim().length === 0) {
            throw new HttpsError("invalid-argument", "title required.");
        }
        if (input.title.length > 120) {
            throw new HttpsError("invalid-argument", "title must be 120 chars or fewer.");
        }
        if ((input.body ?? "").length > 2000) {
            throw new HttpsError("invalid-argument", "body must be 2000 chars or fewer.");
        }

        const validCategories = ["prayer", "study", "question", "general", "announcement"];
        const category = validCategories.includes(input.category) ? input.category : "general";

        const db = getFirestore();
        const now = Timestamp.now();

        // Fetch author's first name
        const userDoc = await db.collection("users").doc(uid).get();
        const authorFirstName = (userDoc.data()?.displayName ?? "Member").split(" ")[0];

        const docRef = await db.collection(`spaces/${input.spaceId}/discussions`).add({
            title: input.title.trim(),
            body: (input.body ?? "").trim(),
            category,
            authorId: uid,
            authorFirstName,
            replyCount: 0,
            isPinned: false,
            isAIGenerated: false,
            lastActivityAt: now,
            createdAt: now,
        });

        return {
            id: docRef.id,
            title: input.title.trim(),
            authorFirstName,
            category,
            replyCount: 0,
            isPinned: false,
            isAIGenerated: true,
            lastActivityAt: now.toDate().toISOString(),
        };
    }
);

export const generateDiscussionFromContent = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<DiscussionDoc> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const input = request.data as GenerateDiscussionFromContentInput;
        if (!input.spaceId || !input.contentId || !input.contentType) {
            throw new HttpsError("invalid-argument", "spaceId, contentId, and contentType required.");
        }

        const db = getFirestore();
        const now = Timestamp.now();

        // Generate a starter title + body based on content type
        const typeLabels: Record<string, string> = {
            livestream: "this week's live stream",
            podcast: "this podcast episode",
            video: "this video",
            post: "this post",
            bibleStudy: "this Bible study",
        };
        const label = typeLabels[input.contentType] ?? "this content";
        const title = `Discussion: What stood out to you from ${label}?`;
        const body = `AI-generated starter:\n1. What was your biggest takeaway?\n2. How does this apply to your week?\n3. What questions do you have?`;

        const docRef = await db.collection(`spaces/${input.spaceId}/discussions`).add({
            title,
            body,
            category: "study",
            authorId: "system",
            authorFirstName: "AMEN",
            replyCount: 0,
            isPinned: false,
            isAIGenerated: true,
            sourceContentId: input.contentId,
            sourceContentType: input.contentType,
            lastActivityAt: now,
            createdAt: now,
        });

        return {
            id: docRef.id,
            title,
            authorFirstName: "AMEN",
            category: "study",
            replyCount: 0,
            isPinned: false,
            isAIGenerated: true,
            lastActivityAt: now.toDate().toISOString(),
        };
    }
);
