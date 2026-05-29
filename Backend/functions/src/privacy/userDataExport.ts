/**
 * userDataExport.ts
 *
 * Callable: requestUserDataExport
 *
 * GDPR Article 20 / CCPA "right to know" — exports all user data as a JSON
 * file stored in Firebase Storage under exports/{uid}/. Returns a signed URL
 * valid for 1 hour so the client can download the file.
 *
 * Rate limit: 1 export per 24-hour window per user.
 *
 * Data collected:
 *   - /users/{uid}                      profile
 *   - /users/{uid}/bereanMemory         AI memory entries
 *   - /users/{uid}/bereanInsights       AI insights
 *   - /users/{uid}/prayerRequests       personal prayer requests
 *   - /users/{uid}/churchNotes          church notes
 *   - /berean_conversations             (userId == uid)
 *   - /berean_messages                  (linked to user conversations)
 *   - /posts                            (authorId == uid)
 *   - /savedPosts                       (userId == uid)
 *
 * Security notes:
 *   - The export file is stored at a private Storage path. The signed URL
 *     is the only way to access it; it expires in 1 hour.
 *   - Rate limit stored in /exportRateLimits/{uid}.
 *   - Internal system fields (hash values, moderation scores) are stripped.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const storage = admin.storage();

const REGION = "us-central1";
const EXPORT_BUCKET = process.env.GCLOUD_PROJECT
    ? `${process.env.GCLOUD_PROJECT}.appspot.com`
    : "amen-app-default.appspot.com";
const SIGNED_URL_EXPIRY_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours
const MAX_DOCS_PER_COLLECTION = 5000; // safety cap per collection

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

async function enforceExportRateLimit(userId: string): Promise<void> {
    const ref = db.collection("exportRateLimits").doc(userId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const now = Date.now();
        const lastExport: number = snap.exists ? (snap.data()?.lastExportAt ?? 0) : 0;

        if (now - lastExport < RATE_LIMIT_WINDOW_MS) {
            const availableAt = new Date(lastExport + RATE_LIMIT_WINDOW_MS).toISOString();
            throw new HttpsError(
                "resource-exhausted",
                `Data export limited to once per 24 hours. Next export available after ${availableAt}.`
            );
        }

        tx.set(ref, { lastExportAt: now, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    });
}

async function collectSubcollection(
    userId: string,
    subcollection: string
): Promise<Record<string, unknown>[]> {
    const snap = await db
        .collection("users")
        .doc(userId)
        .collection(subcollection)
        .limit(MAX_DOCS_PER_COLLECTION)
        .get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function collectTopLevelByField(
    collection: string,
    field: string,
    userId: string
): Promise<Record<string, unknown>[]> {
    const snap = await db
        .collection(collection)
        .where(field, "==", userId)
        .limit(MAX_DOCS_PER_COLLECTION)
        .get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function collectBereanMessages(
    conversations: Array<{ id: string }>
): Promise<Record<string, unknown>[]> {
    if (conversations.length === 0) return [];
    const convIds = conversations.map((c) => c.id);
    const results: Record<string, unknown>[] = [];

    for (let i = 0; i < convIds.length; i += 30) {
        const chunk = convIds.slice(i, i + 30);
        const snap = await db
            .collection("berean_messages")
            .where("conversationId", "in", chunk)
            .limit(MAX_DOCS_PER_COLLECTION)
            .get();
        snap.docs.forEach((d) => results.push({ id: d.id, ...d.data() }));
    }

    return results;
}

// Strip fields that are internal system artifacts, not user-generated data.
const STRIP_FIELDS = new Set([
    "nameKeywords",
    "displayNameLowercase",
    "usernameLowercase",
    "moderationScore",
    "trustScore",
    "riskScore",
    "internalFlags",
    "schemaVersion",
]);

function stripInternalFields(obj: Record<string, unknown>): Record<string, unknown> {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
        if (!STRIP_FIELDS.has(k)) {
            out[k] = v;
        }
    }
    return out;
}

// ── Callable ──────────────────────────────────────────────────────────────────

export const requestUserDataExport = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 300, memory: "512MiB" },
    async (request: CallableRequest) => {
        const userId = requireAuth(request);

        // Rate-limit before doing any work.
        await enforceExportRateLimit(userId);

        logger.info("[requestUserDataExport] Building export for user", { userId });

        // ── Collect all user data ──────────────────────────────────────────────

        const [
            userDoc,
            bereanMemory,
            bereanInsights,
            prayerRequests,
            churchNotes,
            bereanConversations,
            posts,
            savedPosts,
        ] = await Promise.all([
            db.collection("users").doc(userId).get(),
            collectSubcollection(userId, "bereanMemory"),
            collectSubcollection(userId, "bereanInsights"),
            collectSubcollection(userId, "prayerRequests"),
            collectSubcollection(userId, "churchNotes"),
            collectTopLevelByField("berean_conversations", "userId", userId),
            collectTopLevelByField("posts", "authorId", userId),
            collectTopLevelByField("savedPosts", "userId", userId),
        ]);

        const bereanMessages = await collectBereanMessages(
            bereanConversations as Array<{ id: string }>
        );

        // ── Assemble export payload ────────────────────────────────────────────

        const profile = userDoc.exists
            ? stripInternalFields({ id: userDoc.id, ...userDoc.data() as Record<string, unknown> })
            : null;

        const exportPayload = {
            exportedAt: new Date().toISOString(),
            userId,
            schemaVersion: 1,
            profile,
            aiHistory: {
                conversations: bereanConversations,
                messages: bereanMessages,
                memory: bereanMemory,
                insights: bereanInsights,
            },
            content: {
                posts,
                savedPosts,
            },
            spiritualData: {
                prayerRequests,
                churchNotes,
            },
        };

        // ── Write to Storage ───────────────────────────────────────────────────

        const timestamp = Date.now();
        const filePath = `exports/${userId}/data-export-${timestamp}.json`;
        const bucket = storage.bucket(EXPORT_BUCKET);
        const file = bucket.file(filePath);

        await file.save(JSON.stringify(exportPayload, null, 2), {
            contentType: "application/json",
            metadata: {
                contentDisposition: `attachment; filename="amen-data-export-${timestamp}.json"`,
                cacheControl: "private, max-age=0",
            },
        });

        // ── Generate signed URL ────────────────────────────────────────────────

        const [signedUrl] = await file.getSignedUrl({
            action: "read",
            expires: Date.now() + SIGNED_URL_EXPIRY_MS,
        });

        // Audit log.
        await db.collection("dataExportAuditLog").add({
            userId,
            filePath,
            exportedAt: FieldValue.serverTimestamp(),
            collectionsIncluded: [
                "profile",
                "berean_conversations",
                "berean_messages",
                "bereanMemory",
                "bereanInsights",
                "prayerRequests",
                "churchNotes",
                "posts",
                "savedPosts",
            ],
        });

        logger.info("[requestUserDataExport] Export complete", { userId, filePath });

        return {
            success: true,
            downloadUrl: signedUrl,
            expiresInSeconds: SIGNED_URL_EXPIRY_MS / 1000,
            filePath,
        };
    }
);
