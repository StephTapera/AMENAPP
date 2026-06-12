/**
 * nis/birthContextEnricher.ts
 * AMEN — NIS Birth Context Enrichment (C2, Lane E, Wave 1)
 *
 * Enriches an existing `notes/{noteId}/birthContext` document by matching
 * the creation timestamp and user's primary church against known service schedules.
 *
 * Called by Lane B's detectionPipeline.ts after the note write event fires.
 *
 * Signature is stable: Lane B imports `enrichBirthContext` by name.
 * Do NOT modify the export signature without coordinating with Lane B.
 */

import * as admin from "firebase-admin";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Public export — consumed by detectionPipeline.ts
// ---------------------------------------------------------------------------

/**
 * Enrich the birthContext doc for a given note + user.
 *
 * Path: notes/{noteId}/birthContext  (single document, not a subcollection)
 *
 * Wave 1 stub:
 *   - Reads users/{uid}/profile.primaryChurchId (if set).
 *   - If found, sets locationMatched: true, confidence: 0.7, churchId.
 *
 * // Wave 2: replace with schedule-aware matching against church service docs.
 */
export async function enrichBirthContext(
    noteId: string,
    uid: string,
): Promise<void> {
    // birthContext is written as a plain doc at notes/{noteId}/birthContext.
    // NISBirthContextService writes it via setData(..., merge: true) on the
    // notes/{noteId} document under the key "birthContext", so we read
    // the parent note doc here.
    const noteRef = db.doc(`notes/${noteId}`);
    const noteSnap = await noteRef.get();
    if (!noteSnap.exists) {
        return;
    }

    const noteData = noteSnap.data() ?? {};
    // Birth context is stored inline on the note document under key "birthContext".
    const birthContext = noteData["birthContext"] as Record<string, unknown> | undefined;
    if (!birthContext) {
        // No birth context captured — flag was off at creation time. No-op.
        return;
    }

    // Load user profile for primaryChurchId.
    const profileRef = db.doc(`users/${uid}/profile`);
    const profileSnap = await profileRef.get();
    if (!profileSnap.exists) {
        return;
    }

    const profile = profileSnap.data() ?? {};
    const primaryChurchId: string | undefined =
        typeof profile["primaryChurchId"] === "string" && profile["primaryChurchId"]
            ? (profile["primaryChurchId"] as string)
            : undefined;

    if (!primaryChurchId) {
        // User has no primary church set — cannot match.
        return;
    }

    // Wave 2: replace stub below with schedule-aware matching.
    // Check church service schedules (services/{churchId}/schedule) for a window
    // within ±90 minutes of birthContext.createdAt. For now, optimistically
    // match if the user has a primaryChurchId — confidence reflects stub quality.
    const enrichedBirthContext: Record<string, unknown> = {
        ...birthContext,
        // Wave 2: replace with schedule-aware matching
        locationMatched: true,
        confidence: 0.7,
        churchId: primaryChurchId,
        // churchName and seriesId populated by Wave 2 after church doc lookup
    };

    await noteRef.set(
        { birthContext: enrichedBirthContext },
        { merge: true }
    );
}
