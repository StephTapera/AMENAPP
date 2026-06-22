/**
 * nis/index.ts
 * AMEN — Notes Intelligence System (NIS)
 * Wave 0 Contracts — FROZEN after tag nis-contracts-v1
 *
 * Function surface contracts.  Lane owners fill in real implementations
 * per wave schedule.  Signatures and exports are frozen; do not change
 * without human approval per NIS build order §10.
 *
 * Deploy: firebase deploy --only functions --project amen-5e359
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { runDetectionPipeline } from "./detectionPipeline";
import { nisDetectScriptureQuote as _nisDetectScriptureQuoteImpl } from "./scriptureQuoteDetector";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

function requireAuth(auth: { uid?: string } | undefined): string {
    if (!auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return auth.uid;
}

function requireString(value: unknown, field: string): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new HttpsError("invalid-argument", `${field} is required.`);
    }
    return value.trim();
}

// ---------------------------------------------------------------------------
// C1 / C3 — SILENT DETECTION PIPELINE
// Trigger: onWrite notes/{noteId}
// Debounced: skip if nis.lastProcessedAt within 30s of write.
// Lane B (Wave 1) owns the implementation.
// ---------------------------------------------------------------------------

export const nisProcessNote = onDocumentWritten(
    { document: "notes/{noteId}", timeoutSeconds: 120, memory: "512MiB" },
    async (event) => {
        const noteId = event.params.noteId;
        const data = event.data?.after?.data();
        if (!data) return; // document deleted — no-op

        // Debounce: skip if processed within last 30 seconds
        const lastProcessed = data.nis?.lastProcessedAt?.toDate?.() as Date | undefined;
        if (lastProcessed) {
            const ageMs = Date.now() - lastProcessed.getTime();
            if (ageMs < 30_000) return;
        }

        // Lane B Wave 1: run detection pipeline → write detections subcollection + graph edges
        await runDetectionPipeline(noteId, data);
    }
);

// ---------------------------------------------------------------------------
// C3 — SCRIPTURE QUOTE DEEP PATH (internal — called by nisProcessNote pipeline)
// Embeds candidate sentences, queries verse corpus in Pinecone, returns matches ≥ 0.86.
// Lane C (Wave 1) owns the implementation.
// ---------------------------------------------------------------------------

// Not exported as a public callable — internal pipeline function.
// Implementation in nis/scriptureQuoteDetector.ts (Lane C, Wave 1).
export async function nisDetectScriptureQuote(
    sentences: string[],
    noteId: string
): Promise<Array<{ sentence: string; verseId: string; score: number }>> {
    // Lane C Wave 1: delegate to pattern-matching implementation.
    // Wave 2+ will swap this for embedding-based Pinecone retrieval without
    // changing this signature.
    return _nisDetectScriptureQuoteImpl(sentences, noteId);
}

// ---------------------------------------------------------------------------
// C5 — DISTILL NOTE
// Callable: { noteId }
// Generates distilled layer via Berean backend proxy.
// Writes layers/distilled with status: proposed. Never auto-approves.
// Lane I (Wave 3) owns the iOS consume; this callable is available in Wave 1.
// ---------------------------------------------------------------------------

export const nisDistillNote = onCall(
    { enforceAppCheck: true, timeoutSeconds: 60, memory: "256MiB" },
    async (request) => {
        const uid = requireAuth(request.auth);
        const noteId = requireString(request.data?.noteId, "noteId");

        // Verify ownership
        const noteRef = db.collection("notes").doc(noteId);
        const noteSnap = await noteRef.get();
        if (!noteSnap.exists || noteSnap.data()?.uid !== uid) {
            throw new HttpsError("not-found", "Note not found.");
        }

        // Lane I (Wave 3): call Berean proxy, write layers/distilled with status: proposed
        // Implementation placeholder — replace with real Berean proxy call in Wave 1.
        await noteRef
            .collection("layers")
            .doc("distilled")
            .set(
                {
                    keyPoints: [],
                    scriptures: [],
                    takeaway: "",
                    status: "proposed",
                    generatedBy: "berean",
                    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: false }
            );

        return { status: "proposed" };
    }
);

// ---------------------------------------------------------------------------
// C4 — PROMOTE PRAYER
// Callable: { noteId, detectionId }
// Creates prayer entity, marks detection accepted, writes graph edge.
// Lane H (Wave 2) owns the iOS UI; callable available Wave 1.
// ---------------------------------------------------------------------------

export const nisPromotePrayer = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = requireAuth(request.auth);
        const noteId = requireString(request.data?.noteId, "noteId");
        const detectionId = requireString(request.data?.detectionId, "detectionId");

        // Verify detection belongs to user's note
        const detectionRef = db
            .collection("notes").doc(noteId)
            .collection("detections").doc(detectionId);
        const detectionSnap = await detectionRef.get();
        if (!detectionSnap.exists) {
            throw new HttpsError("not-found", "Detection not found.");
        }
        const detection = detectionSnap.data()!;
        if (detection.type !== "prayer") {
            throw new HttpsError("invalid-argument", "Detection is not a prayer type.");
        }

        const prayerId = db.collection("users").doc(uid).collection("prayers").doc().id;

        const batch = db.batch();

        // Write prayer entity
        const prayerRef = db.collection("users").doc(uid).collection("prayers").doc(prayerId);
        batch.set(prayerRef, {
            text: detection.payload?.text ?? detection.payload?.rawText ?? "",
            status: "requested",
            sourceNoteId: noteId,
            sourceDetectionId: detectionId,
            subjectName: detection.payload?.name ?? null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            statusHistory: [{ status: "requested", at: admin.firestore.FieldValue.serverTimestamp() }],
        });

        // Mark detection accepted
        batch.update(detectionRef, {
            status: "accepted",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Write graph edge note → prayer
        const edgeRef = db.collection("users").doc(uid).collection("graphEdges").doc();
        batch.set(edgeRef, {
            from: { type: "note", nodeId: noteId },
            to: { type: "prayer", nodeId: prayerId, label: detection.payload?.text ?? "" },
            weight: detection.confidence ?? 0.8,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            sourceDetectionId: detectionId,
        });

        await batch.commit();

        return { prayerId, status: "requested" };
    }
);

// ---------------------------------------------------------------------------
// C1 — RESOLVE DETECTION
// Callable: { noteId, detectionId, action: "accept" | "dismiss" }
// Single write path for detection status updates.
// ---------------------------------------------------------------------------

export const nisResolveDetection = onCall(
    { enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request) => {
        const uid = requireAuth(request.auth);
        const noteId = requireString(request.data?.noteId, "noteId");
        const detectionId = requireString(request.data?.detectionId, "detectionId");
        const action = request.data?.action;

        if (action !== "accept" && action !== "dismiss") {
            throw new HttpsError("invalid-argument", "action must be 'accept' or 'dismiss'.");
        }

        // Verify ownership via note
        const noteRef = db.collection("notes").doc(noteId);
        const noteSnap = await noteRef.get();
        if (!noteSnap.exists || noteSnap.data()?.uid !== uid) {
            throw new HttpsError("permission-denied", "Not authorized.");
        }

        await db
            .collection("notes").doc(noteId)
            .collection("detections").doc(detectionId)
            .update({
                status: action === "accept" ? "accepted" : "dismissed",
                resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        return { status: action === "accept" ? "accepted" : "dismissed" };
    }
);

// ---------------------------------------------------------------------------
// C6 — RESURFACE SCHEDULER
// Scheduled: weekly, per-user fanout via task queue.
// Selects ≤ 1 note/user/week. Anti-addiction cap enforced server-side.
// Lane J (Wave 3) owns the full implementation.
// ---------------------------------------------------------------------------

export const nisResurfaceScheduler = onSchedule(
    { schedule: "every monday 09:00", timeoutSeconds: 540, memory: "256MiB" },
    async (_event) => {
        // Lane J (Wave 3): fan out via task queue per user, select ≤ 1 note/user/week
        // Implementation placeholder — replace with real fan-out in Wave 3.
        console.log("[NIS] nisResurfaceScheduler fired — Wave 3 implementation pending.");
    }
);

// ---------------------------------------------------------------------------
// C8 — MIGRATION
// nisMigrationStart: callable { content, source }  — creates job doc, enqueues batch
// nisMigrationProcessBatch: task handler (Cloud Tasks) — resumable, idempotent on cursor
// Lane L (Wave 4) owns the full implementation.
// ---------------------------------------------------------------------------

export const nisMigrationStart = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = requireAuth(request.auth);
        const content = requireString(request.data?.content, "content");
        const source = request.data?.source as string;

        if (!["paste", "shareSheet", "fileImport"].includes(source)) {
            throw new HttpsError("invalid-argument", "source must be paste, shareSheet, or fileImport.");
        }

        const jobRef = db.collection("migrations").doc(uid).collection("jobs").doc();
        await jobRef.set({
            status: "queued",
            totalItems: 0,
            processedItems: 0,
            classifiedSpiritual: 0,
            cursor: null,
            source,
            contentLength: content.length,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Lane L (Wave 4): enqueue batch processing via Cloud Tasks
        // Implementation placeholder.

        return { jobId: jobRef.id, status: "queued" };
    }
);

// ---------------------------------------------------------------------------
// C9b — BUILD COMPOSITE
// Trigger: Firestore write on notes/{noteId} when shared to a space
//          with matching birthContext.churchId + date.
// Updates spaces/{spaceId}/composites/{serviceKey} respecting NoteShare visibility.
// Lane N (Wave 4) owns the full implementation.
// ---------------------------------------------------------------------------

// Not wired as a standalone trigger here — triggered by nisProcessNote pipeline
// when NoteShare visibility + Space membership conditions are met.
// Lane N adds the full trigger in Wave 4.
export async function nisBuildComposite(
    _spaceId: string,
    _serviceKey: string,
    _noteId: string,
    _uid: string
): Promise<void> {
    // Wave 4: read note + NoteShare visibility + space membership, update composite
    return;
}

// ---------------------------------------------------------------------------
// C7 — TOPIC READ MODEL
// Trigger: onWrite users/{uid}/graphEdges/{edgeId}
// Maintains users/{uid}/topics counters.
// Lane K (Wave 3) owns the full implementation.
// ---------------------------------------------------------------------------

export const nisTopicReadModel = onDocumentWritten(
    {
        document: "users/{uid}/graphEdges/{edgeId}",
        timeoutSeconds: 30,
        memory: "256MiB",
    },
    async (event) => {
        const uid = event.params.uid;
        const data = event.data?.after?.data();
        if (!data) return;

        const toNode = data.to;
        if (toNode?.type !== "topic" || !toNode?.label) return;

        const topicLabel: string = toNode.label;
        const topicId = topicLabel.toLowerCase().replace(/\s+/g, "_");

        const topicRef = db.collection("users").doc(uid).collection("topics").doc(topicId);

        // Lane K (Wave 3): compute full counters via aggregation
        // Minimal increment placeholder — replace with full aggregation in Wave 3.
        await topicRef.set(
            {
                label: topicLabel,
                noteCount: admin.firestore.FieldValue.increment(event.data?.after?.exists ? 1 : -1),
                prayerCount: 0,
                verseCount: 0,
                sermonCount: 0,
                recentNoteIds: [],
            },
            { merge: true }
        );
    }
);
