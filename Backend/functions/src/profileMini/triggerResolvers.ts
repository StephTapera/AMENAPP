/**
 * triggerResolvers.ts
 *
 * Resolves the surface-specific artifact (thread, post) that contextualizes
 * a UserProfileMini suggestion. Returns null gracefully on any missing data.
 *
 * No writes. No PII logged beyond uid. Max 3 Firestore reads per resolver.
 */

import * as admin from "firebase-admin";

const db = admin.firestore();

export type TriggerArtifactType = "openTableThread" | "prayerPost" | "testimonyPost";
export type ViewerState = "unread" | "read" | "replied" | "prayedToday" | "viewed" | "unknown";

export interface ResolvedTrigger {
    artifactType: TriggerArtifactType;
    artifactId: string;
    title: string | null;
    topic: string | null;
    viewerState: ViewerState;
}

/**
 * Find the most recent OpenTable thread shared by both viewer and target.
 * ViewerState is derived from participantActivity map in the thread doc.
 * Precedence: replied > read > unread.
 * Reads: up to 2 (viewer threads + target thread ID set).
 */
export async function resolveOpenTableTrigger(
    viewerUid: string,
    targetUid: string,
    specificArtifactId?: string
): Promise<ResolvedTrigger | null> {
    try {
        let sharedDoc: admin.firestore.DocumentSnapshot | undefined;

        if (specificArtifactId) {
            // Caller already knows which thread — fetch it directly (1 read).
            const snap = await db.collection("openTableThreads").doc(specificArtifactId).get();
            if (!snap.exists) return null;
            sharedDoc = snap;
        } else {
            // Find the most recent thread both participants share.
            const [viewerSnap, targetSnap] = await Promise.all([
                db.collection("openTableThreads")
                    .where("participantIds", "array-contains", viewerUid)
                    .orderBy("lastActivityAt", "desc")
                    .limit(20)
                    .get(),
                db.collection("openTableThreads")
                    .where("participantIds", "array-contains", targetUid)
                    .limit(50)
                    .get(),
            ]);

            const targetThreadIds = new Set(targetSnap.docs.map(d => d.id));
            sharedDoc = viewerSnap.docs.find(d => targetThreadIds.has(d.id));
            if (!sharedDoc) return null;
        }

        const data = sharedDoc.data()!;
        const activity = data.participantActivity?.[viewerUid];

        // Precedence: replied > read > unread
        let viewerState: ViewerState = "unread";
        if (activity?.repliedAt) {
            viewerState = "replied";
        } else if (activity?.lastSeenAt) {
            viewerState = "read";
        }

        return {
            artifactType: "openTableThread",
            artifactId: sharedDoc.id,
            title: data.title || null,
            topic: data.topic || null,
            viewerState,
        };
    } catch {
        return null;
    }
}

/**
 * Find the most recent prayer post by the target.
 * Detects whether the viewer has prayed for it today.
 * Reads: 1 (post) + 1 (viewer prayer interaction) = 2 max.
 */
export async function resolvePrayerTrigger(
    targetUid: string,
    viewerUid: string,
    specificArtifactId?: string
): Promise<ResolvedTrigger | null> {
    try {
        let postId: string;
        let postData: FirebaseFirestore.DocumentData;

        if (specificArtifactId) {
            const snap = await db.collection("posts").doc(specificArtifactId).get();
            if (!snap.exists) return null;
            postId = snap.id;
            postData = snap.data()!;
        } else {
            const snap = await db.collection("posts")
                .where("authorId", "==", targetUid)
                .where("category", "==", "prayer")
                .orderBy("createdAt", "desc")
                .limit(1)
                .get();

            if (snap.empty) return null;
            postId = snap.docs[0].id;
            postData = snap.docs[0].data();
        }

        // Check if the viewer has prayed for this post today (1 additional read).
        let viewerState: ViewerState = "unknown";
        try {
            const prayedSnap = await db
                .collection("posts").doc(postId)
                .collection("prayers").doc(viewerUid)
                .get();
            if (prayedSnap.exists) {
                const prayedAt = prayedSnap.data()?.createdAt?.toDate?.();
                const today = new Date();
                const isPrayedToday = prayedAt &&
                    prayedAt.getFullYear() === today.getFullYear() &&
                    prayedAt.getMonth() === today.getMonth() &&
                    prayedAt.getDate() === today.getDate();
                viewerState = isPrayedToday ? "prayedToday" : "unknown";
            }
        } catch {
            // Non-fatal: prayer check failure falls back to unknown.
        }

        return {
            artifactType: "prayerPost",
            artifactId: postId,
            title: postData.title || null,
            topic: (postData.tags as string[] || [])[0] || null,
            viewerState,
        };
    } catch {
        return null;
    }
}

/**
 * Find the most recent testimony post by the target.
 * Detects whether the viewer has already viewed it.
 * Reads: 1 (post) + 1 (viewer view check) = 2 max.
 */
export async function resolveTestimonyTrigger(
    targetUid: string,
    viewerUid: string,
    specificArtifactId?: string
): Promise<ResolvedTrigger | null> {
    try {
        let postId: string;
        let postData: FirebaseFirestore.DocumentData;

        if (specificArtifactId) {
            const snap = await db.collection("posts").doc(specificArtifactId).get();
            if (!snap.exists) return null;
            postId = snap.id;
            postData = snap.data()!;
        } else {
            const snap = await db.collection("posts")
                .where("authorId", "==", targetUid)
                .where("category", "==", "testimony")
                .orderBy("createdAt", "desc")
                .limit(1)
                .get();

            if (snap.empty) return null;
            postId = snap.docs[0].id;
            postData = snap.docs[0].data();
        }

        // Check if viewer has already viewed this testimony (1 additional read).
        let viewerState: ViewerState = "unread";
        try {
            const viewedSnap = await db
                .collection("posts").doc(postId)
                .collection("testimonyViews").doc(viewerUid)
                .get();
            if (viewedSnap.exists) {
                viewerState = "viewed";
            }
        } catch {
            // Non-fatal: view check failure falls back to unread.
        }

        return {
            artifactType: "testimonyPost",
            artifactId: postId,
            title: postData.title || null,
            topic: (postData.tags as string[] || [])[0] || null,
            viewerState,
        };
    } catch {
        return null;
    }
}
