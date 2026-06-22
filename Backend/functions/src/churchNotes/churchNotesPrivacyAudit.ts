/**
 * Privacy + permissions audit trail for Church Notes.
 *
 * Writes an immutable event under `churchNotes/{noteId}/events/{eventId}`
 * whenever a privacy-relevant field changes — independently of which code
 * path made the change. This means direct client mutations, callable
 * writes, and admin scripts all produce the same audit record.
 *
 * Audited fields:
 *   • permission        — privateNote / shared / public
 *   • isPublic
 *   • sharedWith        — collaborator UID list on the note doc
 *
 * Collaborator-role changes already audit via `audit()` in
 * `shareChurchNoteWithCollaborators` / `updateChurchNotePermissions`;
 * this trigger covers the remaining direct-client privacy mutations.
 *
 * The /events subcollection has `allow write: if false` at the Firestore
 * rules layer, so clients cannot forge or tamper with audit entries.
 */
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const db = admin.firestore();

interface PrivacyDelta {
    field: string;
    previousValue: unknown;
    newValue:      unknown;
}

function diffPrivacyFields(
    before: FirebaseFirestore.DocumentData | undefined,
    after:  FirebaseFirestore.DocumentData | undefined
): PrivacyDelta[] {
    if (!before || !after) return [];
    const deltas: PrivacyDelta[] = [];

    const scalar = ["permission", "isPublic"];
    for (const field of scalar) {
        if (before[field] !== after[field]) {
            deltas.push({ field, previousValue: before[field] ?? null, newValue: after[field] ?? null });
        }
    }

    const beforeShared = Array.isArray(before.sharedWith) ? [...before.sharedWith].sort() : [];
    const afterShared  = Array.isArray(after.sharedWith)  ? [...after.sharedWith].sort()  : [];
    const sharedChanged =
        beforeShared.length !== afterShared.length ||
        beforeShared.some((v: unknown, i: number) => v !== afterShared[i]);
    if (sharedChanged) {
        deltas.push({ field: "sharedWith", previousValue: beforeShared, newValue: afterShared });
    }

    return deltas;
}

export const auditChurchNotePrivacyChange = onDocumentUpdated(
    "churchNotes/{noteId}",
    async (event) => {
        const noteId = event.params.noteId;
        const before = event.data?.before.data();
        const after  = event.data?.after.data();
        if (!before || !after) return;

        const deltas = diffPrivacyFields(before, after);
        if (deltas.length === 0) return;

        // Best-effort actor inference. Firestore triggers don't have an authenticated
        // request context, so we fall back to the note owner. Clients should call the
        // dedicated callables when they want their UID recorded as the actor explicitly.
        const actorUid: string | null =
            (typeof after.lastUpdatedByUid === "string" && after.lastUpdatedByUid) ||
            (typeof after.userId === "string" && after.userId) ||
            null;

        try {
            await db.collection("churchNotes")
                .doc(noteId)
                .collection("events")
                .add({
                    eventType:   "privacy_changed",
                    actorUid,
                    deltas,
                    source:      "firestore_trigger",
                    createdAt:   admin.firestore.FieldValue.serverTimestamp(),
                });
            logger.info("[churchNotes] privacy audit written", {
                noteId,
                fields: deltas.map((d) => d.field),
            });
        } catch (err) {
            // Never fail the user's write because of an audit log issue — log and continue.
            logger.warn("[churchNotes] privacy audit write failed", {
                noteId,
                error: err instanceof Error ? err.message : String(err),
            });
        }
    },
);
